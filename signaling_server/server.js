import { WebSocketServer } from 'ws';
import { handleMessage } from './message-handler.js';
import { removeSocket } from './room-manager.js';

const PORT = process.env.PORT ? Number(process.env.PORT) : 9090;

// keepalive ping 주기 (ms).
// 30초마다 ping을 보내 클라이언트 생존 여부를 확인한다.
// pong 응답이 없으면 좀비 연결(zombie connection)로 판단해 소켓을 강제 종료한다.
// 좀비 연결: 네트워크가 단절됐지만 서버가 이를 감지하지 못해 방 슬롯을 점유하는 상태.
const PING_INTERVAL_MS = 30_000;

const wss = new WebSocketServer({ port: PORT });

wss.on('listening', () => {
  console.log(`Signaling server listening on ws://0.0.0.0:${PORT}`);
});

wss.on('connection', (socket, req) => {
  const ip = req.socket.remoteAddress;
  console.log(`[connect] ${ip}`);

  // ── Keepalive ─────────────────────────────────────────────────────────────
  // isAlive 플래그: pong 응답을 받을 때마다 true로 재설정된다.
  // ping 시점에 false면 이전 ping에 응답하지 않은 것 → 좀비 연결 → 강제 종료.
  //
  // web_socket_channel(Flutter)은 ws ping/pong을 자동으로 처리하므로
  // 클라이언트 측에 별도 코드를 추가할 필요가 없다.
  socket.isAlive = true;
  socket.on('pong', () => {
    socket.isAlive = true;
  });

  const pingInterval = setInterval(() => {
    if (!socket.isAlive) {
      console.log(`[ping-timeout] ${ip} — no pong, terminating`);
      // terminate(): close()보다 즉각적인 강제 종료.
      // close()는 FIN 핸드셰이크를 기다리지만, terminate()는 바로 소켓을 파괴한다.
      socket.terminate();
      return;
    }
    socket.isAlive = false;
    socket.ping(); // ws 표준 ping 프레임 전송
  }, PING_INTERVAL_MS);

  socket.on('message', (data) => {
    handleMessage(socket, data.toString());
  });

  socket.on('close', () => {
    // 소켓이 닫히면 ping 타이머도 함께 정리해야 메모리 누수가 없다
    clearInterval(pingInterval);
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
