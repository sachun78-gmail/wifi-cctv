import { createRoom, joinRoom, getPeer } from './room-manager.js';

function send(socket, data) {
  if (socket && socket.readyState === 1 /* OPEN */) {
    socket.send(JSON.stringify(data));
  }
}

export function handleMessage(socket, raw) {
  let msg;
  try {
    msg = JSON.parse(raw);
  } catch {
    send(socket, { type: 'room_error', message: '잘못된 메시지 형식입니다.' });
    return;
  }

  const { type } = msg;

  if (type === 'create_room') {
    const roomId = createRoom(socket);
    send(socket, { type: 'room_created', roomId });
    return;
  }

  if (type === 'join_room') {
    const { roomId } = msg;
    const result = joinRoom(roomId, socket);
    if (result.error) {
      send(socket, { type: 'room_error', message: result.error });
      return;
    }
    const { room } = result;
    send(room.camera, { type: 'room_joined', roomId });
    send(room.viewer, { type: 'room_joined', roomId });
    return;
  }

  // offer, answer, candidate — 상대방에게 그대로 중계
  if (type === 'offer' || type === 'answer' || type === 'candidate') {
    const { roomId } = msg;
    const peer = getPeer(roomId, socket);
    if (!peer) {
      send(socket, { type: 'room_error', message: '상대방이 연결되어 있지 않습니다.' });
      return;
    }
    send(peer, msg);
    return;
  }

  send(socket, { type: 'room_error', message: `알 수 없는 메시지 타입: ${type}` });
}
