import { describe, it, before, after, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { WebSocket, WebSocketServer } from 'ws';
import { handleMessage } from '../message-handler.js';
import { getRooms, removeSocket } from '../room-manager.js';

// 테스트용 인메모리 서버 (포트 9999)
const TEST_PORT = 9999;

function waitForMessage(socket) {
  return new Promise((resolve) => {
    socket.once('message', (data) => resolve(JSON.parse(data.toString())));
  });
}

function connect() {
  return new Promise((resolve) => {
    const ws = new WebSocket(`ws://localhost:${TEST_PORT}`);
    ws.once('open', () => resolve(ws));
  });
}

let wss;

before(() => {
  return new Promise((resolve) => {
    wss = new WebSocketServer({ port: TEST_PORT });
    wss.on('connection', (socket) => {
      socket.on('message', (data) => handleMessage(socket, data.toString()));
      socket.on('close', () => {
        const result = removeSocket(socket);
        if (result?.peer) {
          result.peer.send(JSON.stringify({ type: 'peer_disconnected' }));
        }
      });
    });
    wss.on('listening', resolve);
  });
});

after(() => {
  return new Promise((resolve) => wss.close(resolve));
});

afterEach(() => {
  // 테스트 간 방 상태 초기화
  getRooms().clear();
});

describe('create_room', () => {
  it('방 생성 시 room_created와 6자리 roomId 반환', async () => {
    const camera = await connect();
    camera.send(JSON.stringify({ type: 'create_room' }));
    const msg = await waitForMessage(camera);
    assert.equal(msg.type, 'room_created');
    assert.match(msg.roomId, /^\d{6}$/);
    camera.close();
  });
});

describe('join_room', () => {
  it('방 참여 시 camera/viewer 양쪽 모두 room_joined 수신', async () => {
    const camera = await connect();
    const viewer = await connect();

    camera.send(JSON.stringify({ type: 'create_room' }));
    const created = await waitForMessage(camera);
    const { roomId } = created;

    const cameraJoined = waitForMessage(camera);
    viewer.send(JSON.stringify({ type: 'join_room', roomId }));
    const viewerJoined = await waitForMessage(viewer);
    const cameraMsg = await cameraJoined;

    assert.equal(viewerJoined.type, 'room_joined');
    assert.equal(cameraMsg.type, 'room_joined');
    assert.equal(viewerJoined.roomId, roomId);

    camera.close();
    viewer.close();
  });

  it('존재하지 않는 방 참여 시 room_error 반환', async () => {
    const viewer = await connect();
    viewer.send(JSON.stringify({ type: 'join_room', roomId: '000000' }));
    const msg = await waitForMessage(viewer);
    assert.equal(msg.type, 'room_error');
    viewer.close();
  });

  it('이미 뷰어가 있는 방 참여 시 room_error 반환', async () => {
    const camera = await connect();
    const viewer1 = await connect();
    const viewer2 = await connect();

    camera.send(JSON.stringify({ type: 'create_room' }));
    const { roomId } = await waitForMessage(camera);

    viewer1.send(JSON.stringify({ type: 'join_room', roomId }));
    await waitForMessage(viewer1); // room_joined

    viewer2.send(JSON.stringify({ type: 'join_room', roomId }));
    const msg = await waitForMessage(viewer2);
    assert.equal(msg.type, 'room_error');

    camera.close();
    viewer1.close();
    viewer2.close();
  });
});

describe('offer / answer / candidate 중계', () => {
  it('카메라가 보낸 offer를 뷰어가 수신', async () => {
    const camera = await connect();
    const viewer = await connect();

    camera.send(JSON.stringify({ type: 'create_room' }));
    const { roomId } = await waitForMessage(camera);

    const cameraJoined = waitForMessage(camera);
    viewer.send(JSON.stringify({ type: 'join_room', roomId }));
    await waitForMessage(viewer);
    await cameraJoined;

    const offer = { type: 'offer', roomId, sdp: { type: 'offer', sdp: 'v=0...' } };
    camera.send(JSON.stringify(offer));
    const received = await waitForMessage(viewer);
    assert.equal(received.type, 'offer');
    assert.deepEqual(received.sdp, offer.sdp);

    camera.close();
    viewer.close();
  });

  it('뷰어가 보낸 answer를 카메라가 수신', async () => {
    const camera = await connect();
    const viewer = await connect();

    camera.send(JSON.stringify({ type: 'create_room' }));
    const { roomId } = await waitForMessage(camera);

    const cameraJoined = waitForMessage(camera);
    viewer.send(JSON.stringify({ type: 'join_room', roomId }));
    await waitForMessage(viewer);
    await cameraJoined;

    const answer = { type: 'answer', roomId, sdp: { type: 'answer', sdp: 'v=0...' } };
    viewer.send(JSON.stringify(answer));
    const received = await waitForMessage(camera);
    assert.equal(received.type, 'answer');

    camera.close();
    viewer.close();
  });

  it('ICE candidate 양방향 중계', async () => {
    const camera = await connect();
    const viewer = await connect();

    camera.send(JSON.stringify({ type: 'create_room' }));
    const { roomId } = await waitForMessage(camera);

    const cameraJoined = waitForMessage(camera);
    viewer.send(JSON.stringify({ type: 'join_room', roomId }));
    await waitForMessage(viewer);
    await cameraJoined;

    const candidate = { type: 'candidate', roomId, candidate: { candidate: 'candidate:1 ...' } };

    camera.send(JSON.stringify(candidate));
    const fromCamera = await waitForMessage(viewer);
    assert.equal(fromCamera.type, 'candidate');

    viewer.send(JSON.stringify(candidate));
    const fromViewer = await waitForMessage(camera);
    assert.equal(fromViewer.type, 'candidate');

    camera.close();
    viewer.close();
  });

  it('상대방 없는 상태에서 offer 전송 시 room_error 반환', async () => {
    const camera = await connect();

    camera.send(JSON.stringify({ type: 'create_room' }));
    const { roomId } = await waitForMessage(camera);

    camera.send(JSON.stringify({ type: 'offer', roomId, sdp: {} }));
    const msg = await waitForMessage(camera);
    assert.equal(msg.type, 'room_error');

    camera.close();
  });
});

describe('peer_disconnected', () => {
  it('카메라가 끊기면 뷰어에게 peer_disconnected 전송', async () => {
    const camera = await connect();
    const viewer = await connect();

    camera.send(JSON.stringify({ type: 'create_room' }));
    const { roomId } = await waitForMessage(camera);

    const cameraJoined = waitForMessage(camera);
    viewer.send(JSON.stringify({ type: 'join_room', roomId }));
    await waitForMessage(viewer);
    await cameraJoined;

    camera.close();
    const msg = await waitForMessage(viewer);
    assert.equal(msg.type, 'peer_disconnected');

    viewer.close();
  });

  it('뷰어가 끊기면 카메라에게 peer_disconnected 전송', async () => {
    const camera = await connect();
    const viewer = await connect();

    camera.send(JSON.stringify({ type: 'create_room' }));
    const { roomId } = await waitForMessage(camera);

    const cameraJoined = waitForMessage(camera);
    viewer.send(JSON.stringify({ type: 'join_room', roomId }));
    await waitForMessage(viewer);
    await cameraJoined;

    viewer.close();
    const msg = await waitForMessage(camera);
    assert.equal(msg.type, 'peer_disconnected');

    camera.close();
  });
});
