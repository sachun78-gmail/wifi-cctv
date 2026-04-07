// 방 구조: { id: string, camera: WebSocket | null, viewer: WebSocket | null }
const rooms = new Map();

function generateRoomId() {
  let id;
  do {
    id = String(Math.floor(Math.random() * 1000000)).padStart(6, '0');
  } while (rooms.has(id));
  return id;
}

export function createRoom(cameraSocket) {
  const id = generateRoomId();
  rooms.set(id, { id, camera: cameraSocket, viewer: null });
  return id;
}

export function joinRoom(roomId, viewerSocket) {
  const room = rooms.get(roomId);
  if (!room) return { error: '존재하지 않는 방입니다.' };
  if (room.viewer) return { error: '이미 뷰어가 연결된 방입니다.' };
  room.viewer = viewerSocket;
  return { room };
}

export function getRoom(roomId) {
  return rooms.get(roomId) ?? null;
}

export function getPeer(roomId, socket) {
  const room = rooms.get(roomId);
  if (!room) return null;
  if (room.camera === socket) return room.viewer;
  if (room.viewer === socket) return room.camera;
  return null;
}

export function removeSocket(socket) {
  for (const [roomId, room] of rooms) {
    if (room.camera === socket) {
      room.camera = null;
      const peer = room.viewer;
      if (!room.viewer) rooms.delete(roomId);
      return { roomId, peer };
    }
    if (room.viewer === socket) {
      room.viewer = null;
      const peer = room.camera;
      if (!room.camera) rooms.delete(roomId);
      return { roomId, peer };
    }
  }
  return null;
}

export function getRooms() {
  return rooms;
}
