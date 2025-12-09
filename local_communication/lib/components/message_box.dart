import 'package:flutter/material.dart';

class MessageBox extends StatelessWidget {
  final String message;
  final bool send;
  const MessageBox({super.key, required this.message, required this.send});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: send ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: send ? Colors.white : Theme.of(context).primaryColor,
            borderRadius: BorderRadius.circular(16),
          ),
          width: MediaQuery.of(context).size.width * 0.6,
          padding: EdgeInsets.all(16),
          margin: EdgeInsets.only(bottom: 16),
          child: Text(
            message,
            style: TextStyle(color: send ? null : Colors.white),
          ),
        ),
      ],
    );
  }
}
