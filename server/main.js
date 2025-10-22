const { Server } = require("socket.io");

const io = new Server();
const users = new Map();

function sendUsers(id) {
    io.emit('users', Array.from(users));
}

io.on("connection", (socket) => {
    console.log('Kullanıcı bağlandı:', socket.id);

    users.set(socket.id, { ip: socket.handshake.headers['x-forwarded-for'] || socket.conn.remoteAddress.split(":")[3], emergency: false });
    sendUsers(socket.id)

    socket.on('users', (_) => {
        sendUsers(socket.id)
    });

    socket.on('message', ({ id, message }) => {
        io.to(id).emit('message', message);
    });

    socket.on('disconnect', () => {
        console.log('Kullanıcı bağlantısı kesildi:', socket.id);
        users.delete(socket.id);
        sendUsers(socket.id)
    });
});

io.listen(3000);