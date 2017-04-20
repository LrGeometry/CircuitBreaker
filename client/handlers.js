import * as utils from "./utils.js";

let chunkSize = 1024 * 16;
let targetBuffer = new Uint8Array(chunkSize);

export default (prims) => {
  return {
    malloc: (data, json, bin) => {
      let ptr = prims.malloc(data.length)
      return json({
        address: ptr,
        length: data.length
      });
    },
    free: (data, json, bin) => {
      prims.free(data.address);
      return json({
        address: data.address
      });
    },
    read: (data, json, bin) => {
      bin(data.length).then((stream) => {
        let addr = data.address;
        let bytes = 0;
        while(bytes < data.length) {
          let toRead = Math.min(chunkSize, data.length-bytes);
          prims.mempeek(addr, toRead, (ab) => {
            stream(ab);
          });
          /*
          prims.read(addr, targetBuffer);
          stream(toRead == chunkSize ? targetBuffer : targetBuffer.slice(0, toRead));
          utils.log("streamed.");*/
          addr = utils.add64(addr, toRead);
          bytes+= toRead;
        }
      });
      //let target = new Uint8Array(data.length);
      //prims.read(data.address, target);
      //return bin(target);
    },
    write: (data, json, bin) => {
      let buffer = new Uint8Array(atob(data.payload).split("").map(function(c) {
        return c.charCodeAt(0);
      }));
      prims.write(data.address, buffer);
      return json({
        address: data.address,
        length: data.length
      });
    },
    invokeGC: (data, json, bin) => {
      prims.invokeGC();
      return json({
      });
    },
    get: (data, json, bin) => {
      json((() => {
        switch(data.field) {
        case "baseAddr": return {value: prims.base};
        case "mainAddr": return {value: prims.mainaddr};
        case "sp": return {value: prims.getSP()};
        case "tls": return {value: prims.getTLS()};
        }
        return {};
      })());
    },
    invokeBridge: (data, json, bin) => {
      return json({
        returnValue: prims.call(data.funcPtr, data.intArgs, data.floatArgs)
      });
    },
    eval: (data, json, bin) => {
      return json({
        returnValue: eval.call(window, data.code).toString()
      });
    },
    ping: (data, json, bin) => {
      return json({
        originTime: json.time
      });
    }
  };
};
