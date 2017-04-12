const fs = require("fs");
const path = require("path");
const os = require("os");

const dnsd = require("dnsd");
const ip = require("ip");
const express = require("express");

let dns = dnsd.createServer((req, res) => {
  if(req.question[0].name == "html5gamepad.com") {
    res.end("173.255.216.50");
  }
  res.end(ip.address())
});

dns.listen(53, "0.0.0.0");

const app = express();

app.get("/", (req, res) => {
  res.end(fs.readFileSync(path.resolve(__dirname, "public/index.html")));
});

app.get("/minmain.js", (req, res) => {
  res.end(fs.readFileSync(path.resolve(__dirname, "public/minmain.js")));
});

app.get("/bundle.js", (req, res) => {
  res.end(fs.readFileSync(path.resolve(__dirname, "public/bundle.js")));
});

app.listen(80, "0.0.0.0", (err) => {
  if(err) {
    console.error("Could not bind port 80");
    process.exit(1);
  }
});
