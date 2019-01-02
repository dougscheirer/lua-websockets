var WebSocketServer = require('ws').Server;
const port = parseInt(process.argv[2]);

var wss = new WebSocketServer({ port: port });

wss.on('connection', function connection(ws) {
  ws.on('message', function incoming(message, flags) {
  	ws.send(message, flags);
  });
});

// also set up a wss server based on some basic pem files
const fs = require('fs');
const https = require('https');
const privateKey = fs.readFileSync('spec/ssl-privatekey.pem');
const certificate = fs.readFileSync('spec/ssl-certificate.pem');

const server = https.createServer({
  key: privateKey,
  cert: certificate
});

const wss_secure = new WebSocketServer({ server: server });

wss_secure.on('connection', function connection(ws) {
  ws.on('message', function incoming(message, flags) {
    ws.send(message, flags);
  });
});

server.listen(port+1);

