// State model for application termination while a modal sheet is presented.

const TERMINAL = new Set(["terminated"]);

function initial(sheetPresented) {
  return {
    status: "running",
    sheetPresented,
    unsavedResult: false,
    illegal: null,
  };
}

function reduce(state, action) {
  const deny = (reason) => ({ ...state, illegal: `${action.type}: ${reason}` });
  const accept = (patch) => ({ ...state, illegal: null, ...patch });

  if (TERMINAL.has(state.status)) return deny("application already terminated");

  switch (action.type) {
  case "SET_UNSAVED_RESULT":
    if (state.status !== "running" && state.status !== "resumed") {
      return deny("results can only change while the application is running");
    }
    return accept({ unsavedResult: action.value });
  case "REQUEST_QUIT":
    if (state.status !== "running" && state.status !== "resumed") {
      return deny("termination is already being coordinated");
    }
    return accept({ status: "preparing" });
  case "PREPARE_COMPLETE":
    if (state.status !== "preparing") return deny("cleanup has not started");
    return accept({ status: state.unsavedResult ? "confirming" : "terminated" });
  case "CONFIRM_DISCARD":
    if (state.status !== "confirming") return deny("no discard confirmation is active");
    return accept({ status: "terminated", unsavedResult: false });
  case "CANCEL_QUIT":
    if (state.status !== "confirming") return deny("termination is not awaiting confirmation");
    return accept({ status: "resumed" });
  default:
    return deny("unknown event");
  }
}

const ALL_ACTIONS = [
  { type: "SET_UNSAVED_RESULT", value: true },
  { type: "SET_UNSAVED_RESULT", value: false },
  { type: "REQUEST_QUIT" },
  { type: "PREPARE_COMPLETE" },
  { type: "CONFIRM_DISCARD" },
  { type: "CANCEL_QUIT" },
];

function legal(state) {
  const result = {};
  for (const action of ALL_ACTIONS) {
    const next = reduce(state, action);
    result[action.type + ("value" in action ? `:${action.value}` : "")] = next.illegal
      ? { legal: false, why: next.illegal }
      : { legal: true, why: null };
  }
  return result;
}

window.TerminationModel = { initial, reduce, legal, TERMINAL };
