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
  let attemptConnection = () => {
    utils.log("Attempting to connect to " + wsPath);
    let ws = new WebSocket(wsPath);
    let handlers = handlerGen(prims);
    let madeConnection = false;

    let streamBeginPromise = Promise.resolve(null);
    
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

      let binaryStream = (length) => {
        // wait for any previous streams to finish. concurrent streams are not allowed.
        return streamBeginPromise = streamBeginPromise.then(() => {
          ws.send(JSON.stringify({
            command: "return",
            jobTag: data.jobTag,
            jobCommand: data.command,
            binaryPayload: true,
            streamingPayload: true,
            binaryLength: length
          }));
          
          return (chunk) => {
            ws.send(chunk);
          };
        });
      };

      try {
        handlers[data.command](data, jsonResponse, binaryStream);
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
      madeConnection = true;
      utils.log("Connected to server.");
    };
    
    ws.onerror = (e) => {
      utils.log("Could not open websocket: " + JSON.stringify(e));
      if(madeConnection) {
        location.reload();
      } else {
        window.setTimeout(attemptConnection, 1000);
      }
    };

    ws.onclose = (e) => {
      utils.log("Websocket closed.");
      if(madeConnection) {
        location.reload();
      }
    };
  };
  
  attemptConnection();

  let last = performance.now();
  let scrollHandler = (t) => {
    let delta = t-last;
    last = t;

    if(navigator.getGamepads().length > 0){
      let joy = navigator.getGamepads()[0].axes[3];
      
      utils.logBox.scrollTop+= delta * joy * 1;
    }
    
    window.requestAnimationFrame(scrollHandler);
  };
  window.requestAnimationFrame(scrollHandler);
})();
