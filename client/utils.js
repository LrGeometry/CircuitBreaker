let logBox = null;

export let loaded = () => {
  logBox = document.getElementById("logregion");
};

export let log = (msg) => {
  //if(window.socket) {
  //  window.socket.send(JSON.stringify({command: "log", message: msg}));
  //}
  logBox.textContent+= msg + "\n";
};

export let dlog = log;

// add a pair of 32-bit words
export let add64 = (addr, off) => {
  if(typeof(off) == 'number')
    off = [off, 0];

  let [alo, ahi] = addr;
  let [blo, bhi] = off;
  
  var nlo = ((alo + blo) & 0xFFFFFFFF) >>> 0;
  var nhi = ((ahi + bhi) & 0xFFFFFFFF) >>> 0;

  // I don't really want to decipher this, but this is probably carrying
  if((nlo < alo && blo > 0) || (nlo == alo && blo != 0)) {
    nhi = ((nhi + 1) & 0xFFFFFFFF) >>> 0;
  } else if(nlo > alo && blo < 0) {
    nhi = ((nhi - 1) & 0xFFFFFFFF) >>> 0;
  }

  return [nlo, nhi];
};

export let add2 = add64;

export let toString64 = function(lo, hi) {
  if(arguments.length == 1) {
    hi = lo[1];
    lo = lo[0];
  }
  let slo = ('00000000' + lo.toString(16)).slice(-8);
  let shi = ('00000000' + hi.toString(16)).slice(-8);
  return '0x' + shi + slo;
};

export let paddr = toString64;

export let isNullPointer = (addr) => {
  return addr[0] == 0 && addr[1] == 0;
};
