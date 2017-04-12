import * as utils from "./utils.js";

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
      let chunkSize = 1024 * 16;
      bin(data.length).then((stream) => {
        let target = new Uint8Array(chunkSize);
        let addr = data.address;
        let bytes = 0;
        while(bytes < data.length) {
          let toRead = Math.min(chunkSize, data.length-bytes);
          prims.read(addr, target);
          stream(target.slice(0, toRead));
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
