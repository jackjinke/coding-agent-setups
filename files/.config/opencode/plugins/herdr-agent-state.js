// installed by herdr
// managed by herdr; reinstalling or updating the integration overwrites this file.
// add custom hooks/plugins beside this file instead of editing it.
// HERDR_INTEGRATION_ID=opencode
// HERDR_INTEGRATION_VERSION=8

import net from "node:net";

const SOURCE = "herdr:opencode";
const AGENT = "opencode";
let reportSeq = Date.now() * 1000;

const childSessions = new Set();
const childStates = new Map();
let rootState = "idle";

function nextReportSeq() {
  reportSeq += 1;
  return reportSeq;
}

function sessionIDFromProperties(properties) {
  return typeof properties?.sessionID === "string" && properties.sessionID
    ? properties.sessionID
    : undefined;
}

function stateFromSessionStatus(status) {
  // session.status carries { type: "idle" | "busy" | "retry" }; older builds used a bare string.
  const kind = typeof status === "string" ? status : status?.type;
  if (typeof kind !== "string") return undefined;
  switch (kind.toLowerCase()) {
    case "idle":
      return "idle";
    case "active":
    case "busy":
    case "pending":
    case "running":
    case "streaming":
    case "working":
    case "retry":
      return "working";
    default:
      return undefined;
  }
}

function request(method, params) {
  const socketPath = process.env.HERDR_SOCKET_PATH;

  if (!socketPath) {
    return Promise.resolve();
  }

  const requestId = `${SOURCE}:${Date.now()}:${Math.floor(Math.random() * 1_000_000)
    .toString()
    .padStart(6, "0")}`;
  const request = {
    id: requestId,
    method,
    params,
  };

  return new Promise((resolve) => {
    let response = "";
    const client = net.createConnection(socketPath, () => {
      client.write(`${JSON.stringify(request)}\n`);
    });

    const finish = () => {
      client.destroy();
      try {
        resolve(response ? JSON.parse(response.trim()) : undefined);
      } catch {
        resolve(undefined);
      }
    };

    client.setTimeout(500, finish);
    client.on("data", (chunk) => {
      response += chunk.toString();
      if (response.includes("\n")) finish();
    });
    client.on("error", finish);
    client.on("end", finish);
    client.on("close", () => resolve(undefined));
  });
}

function reportRequest(method, params, paneID) {
  const targetPaneID = paneID ?? process.env.HERDR_PANE_ID;
  if (!targetPaneID) return Promise.resolve();
  return request(method, {
    pane_id: targetPaneID,
    source: SOURCE,
    agent: AGENT,
    seq: nextReportSeq(),
    ...params,
  });
}

function reportSession(sessionID, sessionStartSource) {
  if (!sessionID) {
    return Promise.resolve();
  }
  const params = { agent_session_id: sessionID };
  if (sessionStartSource) {
    params.session_start_source = sessionStartSource;
  }
  return reportRequest("pane.report_agent_session", params);
}

function reportState(state, sessionID, paneID) {
  const params = { state };
  if (sessionID) {
    params.agent_session_id = sessionID;
  }
  return reportRequest("pane.report_agent", params, paneID);
}

const childPanes = new Map();
const childAgents = new Map();

async function paneForChildSession(sessionID) {
  childPanes.delete(sessionID);

  const workspaceID = process.env.HERDR_WORKSPACE_ID;
  const listResponse = await request("pane.list", {
    ...(workspaceID ? { workspace_id: workspaceID } : {}),
  });
  const panes = listResponse?.result?.panes;
  if (!Array.isArray(panes)) return undefined;

  for (const pane of panes) {
    if (!pane?.pane_id || pane.pane_id === process.env.HERDR_PANE_ID) continue;
    const processResponse = await request("pane.process_info", {
      pane_id: pane.pane_id,
    });
    const processes = processResponse?.result?.process_info?.foreground_processes;
    if (!Array.isArray(processes)) continue;
    const matched = processes.some((process) => {
      const argv = process?.argv;
      if (!Array.isArray(argv)) return false;
      const sessionIndex = argv.indexOf("--session");
      return sessionIndex >= 0 && argv[sessionIndex + 1] === sessionID;
    });
    if (matched) {
      childPanes.set(sessionID, pane.pane_id);
      return pane.pane_id;
    }
  }
  return undefined;
}

async function reportChildMetadata(sessionID) {
  const childAgent = childAgents.get(sessionID);
  if (!childAgent) return;
  const paneID = await paneForChildSession(sessionID);
  if (!paneID) return;
  await request("pane.report_metadata", {
    pane_id: paneID,
    source: SOURCE,
    agent: AGENT,
    seq: nextReportSeq(),
    display_agent: `${AGENT} (${childAgent})`,
    clear_title: true,
  });
}

async function reportChildState(state, sessionID) {
  const paneID = await paneForChildSession(sessionID);
  if (!paneID) return;
  await Promise.all([
    reportState(state, sessionID, paneID),
    reportChildMetadata(sessionID),
  ]);
}

function aggregateState() {
  const states = [rootState, ...childStates.values()];
  if (states.includes("blocked")) return "blocked";
  if (states.includes("working")) return "working";
  return "idle";
}

function reportAggregateState() {
  return reportState(aggregateState());
}

export const HerdrAgentStatePlugin = async () => {
  if (
    process.env.HERDR_ENV !== "1" ||
    !process.env.HERDR_SOCKET_PATH ||
    !process.env.HERDR_PANE_ID
  ) {
    return {};
  }

  return {
    "chat.message": async ({ sessionID }) => {
      if (sessionID && childSessions.has(sessionID)) {
        childStates.set(sessionID, "working");
        await Promise.all([
          reportChildState("working", sessionID),
          reportAggregateState(),
        ]);
        return;
      }
      rootState = "working";
      await reportState("working", sessionID);
    },
    event: async ({ event }) => {
      const type = event?.type;
      const properties = event?.properties ?? {};
      const sessionID = sessionIDFromProperties(properties);

      const info = properties.info;
      if (info?.id && info.parentID) {
        childSessions.add(info.id);
        if (typeof info.agent === "string" && info.agent) {
          childAgents.set(info.id, info.agent);
        }
      }
      if (sessionID && childSessions.has(sessionID)) {
        switch (type) {
          case "session.status": {
            const state = stateFromSessionStatus(properties.status);
            if (state) childStates.set(sessionID, state);
            break;
          }
          case "tool.execute.before":
          case "tool.execute.after":
          case "permission.replied":
          case "question.replied":
          case "question.rejected":
          case "session.compacted":
            childStates.set(sessionID, "working");
            break;
          case "permission.asked":
          case "question.asked":
          case "session.error":
            childStates.set(sessionID, "blocked");
            break;
          case "session.idle":
            childStates.set(sessionID, "idle");
            break;
          case "session.deleted":
            childStates.delete(sessionID);
            childSessions.delete(sessionID);
            childPanes.delete(sessionID);
            childAgents.delete(sessionID);
            break;
          default:
            break;
        }
        const childState = childStates.get(sessionID);
        await Promise.all([
          childState
            ? reportChildState(childState, sessionID)
            : reportChildMetadata(sessionID),
          reportAggregateState(),
        ]);
        return;
      }

      switch (type) {
        case "session.created":
          // A root session.created is a genuine new-session start (child
          // creates are dropped above). Signal it so herdr replaces the pane's
          // prior session id instead of treating the change as cross-talk.
          await reportSession(sessionID, "new");
          break;
        case "session.updated":
          await reportSession(sessionID);
          break;
        case "session.status": {
          const state = stateFromSessionStatus(properties.status);
          if (state) {
            rootState = state;
            await reportAggregateState();
          } else {
            await reportSession(sessionID);
          }
          break;
        }
        case "tool.execute.before":
        case "tool.execute.after":
        case "permission.replied":
        case "question.replied":
        case "question.rejected":
        case "session.compacted":
          rootState = "working";
          await reportAggregateState();
          break;
        case "permission.asked":
        case "question.asked":
        case "session.error":
          rootState = "blocked";
          await reportAggregateState();
          break;
        case "session.idle":
          rootState = "idle";
          await reportAggregateState();
          break;
        case "session.deleted":
          break;
        default:
          break;
      }
    },
  };
};
