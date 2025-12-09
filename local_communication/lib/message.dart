import 'package:flutter/material.dart';
import 'package:get/state_manager.dart';
import 'package:local_communication/components/message_box.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

class Message extends StatelessWidget {
  final String id, ip;
  final IO.Socket socket;
  const Message({
    super.key,
    required this.id,
    required this.ip,
    required this.socket,
  });

  @override
  Widget build(BuildContext context) {
    ScrollController scrollController = ScrollController();
    TextEditingController textEditingController = TextEditingController();

    RxList message = [].obs;

    void scroll() {
      scrollController.animateTo(
        scrollController.position.maxScrollExtent,
        duration: Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }

    socket.on('message', (data) {
      message.add({'send': false, 'message': data});
      scroll();
    });

    return Scaffold(
      appBar: AppBar(title: Text(ip)),
      body: Column(
        children: [
          Obx(
            () => Expanded(
              child: ListView.builder(
                padding: EdgeInsets.all(16),
                shrinkWrap: true,
                controller: scrollController,
                itemBuilder:
                    (context, index) => MessageBox(
                      message: message[index]['message'],
                      send: message[index]['send'],
                    ),
                itemCount: message.length,
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: TextField(
                      controller: textEditingController,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(40),
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton.filled(
                  
                  onPressed: () {
                    if (textEditingController.text.isNotEmpty) {
                      String msg = textEditingController.text;
                      textEditingController.clear();
                      socket.emit('message', {'id': id, 'message': msg});
                      message.add({'send': true, 'message': msg});
                      scroll();
                    }
                  },
                  icon: Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
