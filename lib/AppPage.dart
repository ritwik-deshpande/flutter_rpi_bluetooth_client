import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

class AppPage extends StatefulWidget {
  final BluetoothDevice server;
  double power = 50.0;
  double temperature = 12.0;
  double speed = 0.0;
  String location = '';
  AppPage({this.server});

  @override
  _AppPage createState() => new _AppPage();
}

class _AppPage extends State<AppPage> {
  BluetoothConnection connection;

  String _messageBuffer = '';
  String message = "";
  Timer timer;
  bool isConnecting = true;

  bool get isConnected => connection != null && connection.isConnected;

  bool isDisconnecting = false;

  @override
  void initState() {
    super.initState();

    BluetoothConnection.toAddress(widget.server.address).then((_connection) {
      print('Connected to the device');
      timer = Timer.periodic(const Duration(seconds: 2), (Timer t){
          _sendMessage("info", 0);
      });

      connection = _connection;
      setState(() {
        isConnecting = false;
        isDisconnecting = false;
      });

      connection.input.listen(_onDataReceived).onDone(() {
        // Example: Detect which side closed the connection
        // There should be `isDisconnecting` flag to show are we are (locally)
        // in middle of disconnecting process, should be set before calling
        // `dispose`, `finish` or `close`, which all causes to disconnect.
        // If we except the disconnection, `onDone` should be fired as result.
        // If we didn't except this (no flag set), it means closing by remote.
        if (isDisconnecting) {
          print('Disconnecting locally!');
        } else {
          print('Disconnected remotely!');
        }
        if (this.mounted) {
          setState(() {});
        }
      });
    }).catchError((error) {
      print('Cannot connect, exception occured');
      print(error);
    });
  }

  @override
  void dispose() {
    // Avoid memory leak (`setState` after dispose) and disconnect
    if (isConnected) {
      isDisconnecting = true;
      connection.dispose();
      connection = null;
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Text command = Text(message);

    return Scaffold(
      appBar: AppBar(title: Text("Navigation Panel")),
      body: SafeArea(
        child: Container(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                alignment: Alignment.center,
                child: Column(
                  // mainAxisSize: ,
                  children: [
                    Flex(
                      mainAxisSize: MainAxisSize.min,
                      direction: Axis.horizontal,
                      children: [
                        Flexible(
                          child: Container(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                CustomButton(Icons.arrow_back, "a", widget.power.round()),
                                SizedBox(
                                  width: 15,
                                ),
                                Flexible(
                                  child: Container(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        command,
                                        // Button
                                        CustomButton(Icons.arrow_upward, "w", widget.power.round()),
                                        SizedBox(height: 110),
                                        CustomButton(Icons.arrow_downward, "s", widget.power.round()),
                                      ],
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 15,
                                ),
                                CustomButton(Icons.arrow_forward, "d", widget.power.round())
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(height: 50,),
              Text("Power Value: " + widget.power.round().toString()),
              Slider(
                value: widget.power,
                max: 100,
                divisions: 5,
                label: widget.power.round().toString(),
                onChanged: (double value) {
                  setState(() {
                    widget.power = value;
                  });
                },
              ),
              Text("Car Temperature: " + widget.temperature.toString() + " F"),
              Text("Speed of the car: " + widget.speed.toString() + " m/s"),
              Text("Location of the car: " + widget.location),


            ],
          ),
        ),
      ),
    );
  }

  GestureDetector CustomButton(IconData icon, String msg, int power) {
    return GestureDetector(
      onTapDown: (details) {
        print("Long pressed");
        _sendMessage(msg, power);
      },
      onTapUp: (details) {
        print("Removed from button");
        _sendMessage("STOP", power);
      },
      child: Container(
        height: 40,
        width: 60,
        decoration: BoxDecoration(
            color: Colors.blueAccent, borderRadius: BorderRadius.circular(4.0)),
        child: Icon(
          icon,
          color: Colors.white,
        ),
      ),
    );
  }

  void _onDataReceived(Uint8List data) {
    // Allocate buffer for parsed data

    print(data);

    int backspacesCounter = 0;
    data.forEach((byte) {
      if (byte == 8 || byte == 127) {
        backspacesCounter++;
      }
    });
    Uint8List buffer = Uint8List(data.length - backspacesCounter);
    int bufferIndex = buffer.length;

    // Apply backspace control character
    backspacesCounter = 0;
    for (int i = data.length - 1; i >= 0; i--) {
      if (data[i] == 8 || data[i] == 127) {
        backspacesCounter++;
      } else {
        if (backspacesCounter > 0) {
          backspacesCounter--;
        } else {
          buffer[--bufferIndex] = data[i];
        }
      }
    }

    // Create message if there is new line character
    String dataString = String.fromCharCodes(buffer);
    print(dataString);

    if (dataString == "key"){
      return;
    }
    List<String> data_list = dataString.split("|");

    setState(() {
      widget.speed = double.parse(data_list[2]);
      widget.temperature = double.parse(data_list[1]);
      widget.location = data_list[0];
    });

    int index = buffer.indexOf(13);
    if (~index != 0) {
      setState(() {
        message = backspacesCounter > 0
            ? _messageBuffer.substring(
                0, _messageBuffer.length - backspacesCounter)
            : _messageBuffer + dataString.substring(0, index);

        _messageBuffer = dataString.substring(index);
      });
    } else {
      _messageBuffer = (backspacesCounter > 0
          ? _messageBuffer.substring(
              0, _messageBuffer.length - backspacesCounter)
          : _messageBuffer + dataString);
    }
  }

  void _sendMessage(String text, int power) async {
    text = text.trim();

    if (text.length > 0) {
      try {
        connection.output.add(utf8.encode(text + "|" + power.toString() + "\r\n"));
        await connection.output.allSent;
      } catch (e) {
        // Ignore error, but notify state
        setState(() {});
      }
    }
  }
}
