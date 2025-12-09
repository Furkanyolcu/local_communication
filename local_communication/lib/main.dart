import 'dart:io';
import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:local_communication/message.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'harita_sayfasi.dart';

void main() {
  runApp(const GetMaterialApp(home: Main()));
}

class Main extends StatefulWidget {
  const Main({super.key});

  @override
  State<Main> createState() => _MainState();
}

class _MainState extends State<Main> {
  late IO.Socket socket;
  RxList users = [].obs;
  RxString ip = "".obs;

    void _openMapPage() {
      Navigator.of(context).push(
    MaterialPageRoute(builder: (context) => DamageMapPage()),
      );
    }

  Future<String?> getLocalIpAddress() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );

    for (final interface in interfaces) {
      for (final addr in interface.addresses) {
        if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
          return ip.value = addr.address;
        }
      }
    }
    return "null";
  }

  @override
  void initState() {
    super.initState();

    if (!(GetPlatform.isWeb)) getLocalIpAddress();

    socket = IO.io(
      'http://192.168.4.4:3000',
      IO.OptionBuilder().setTransports(['websocket']).build(),
    );

    socket.onConnect((_) {
      print('connect');
    });

    socket.on('users', (data) {
      users.value = data;

      print(users);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Text('Local Communication'),
            Text('Emergency'),
            Obx(
              () => Text(
                "My IP: ${ip.value}",
                style: TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.map),
            onPressed: _openMapPage,
            tooltip: 'Map',
          ),
        ],
      ),
      body: Obx(
        () => ListView.builder(
          itemBuilder:
              (context, index) =>
                  users[index][0] == socket.id
                      ? SizedBox()
                      : ListTile(
                        onTap:
                            () => Get.to(
                              Message(
                                id: users[index][0],
                                ip: users[index][1]['ip'],
                                socket: socket,
                              ),
                            ),
                        leading: Icon(Icons.link),
                        title: Text(users[index][1]['ip'].toString()),
                        subtitle: Text(users[index][0].toString()),
                        trailing: Icon(Icons.navigate_next_rounded),
                      ),
          itemCount: users.length,
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.red,
        onPressed: ()  {
           FlameAudio.play('acil.wav');
        },
        child: Icon(Icons.warning_amber_rounded,color: Colors.white,),
      ),
    );
  }
}
