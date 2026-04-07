import { WebSocketServer } from 'ws';
import { handleMessage } from './message-handler.js';
import { removeSocket } from './room-manager.js';

const PORT = process.env.PORT ? Number(process.env.PORT) : 9090;

const wss = new WebSocketServer({ port: PORT });

wss.on('listening', () => {
  console.log(`Signaling server listening on ws://0.0.0.0:${PORT}`);
});

wss.on('connection', (socket, req) => {
  const ip = req.socket.remoteAddress;
  console.log(`[connect] ${ip}`);

  socket.on('message', (data) => {
    handleMessage(socket, data.toString());
  });

  socket.on('close', () => {
    console.log(`[disconnect] ${ip}`);
    const result = removeSocket(socket);
    if (result?.peer) {
      result.peer.send(JSON.stringify({ type: 'peer_disconnected' }));
    }
  });

  socket.on('error', (err) => {
    console.error(`[error] ${ip}: ${err.message}`);
  });
});

export default wss;
