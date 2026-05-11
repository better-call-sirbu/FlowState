import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/timer_bloc.dart';
import 'package:hive/hive.dart';

class StudyRoomScreen extends StatefulWidget {
  const StudyRoomScreen({super.key});

  @override
  State<StudyRoomScreen> createState() => _StudyRoomScreenState();
}

class _StudyRoomScreenState extends State<StudyRoomScreen> {
  List<String> _tasks = [];
  final TextEditingController _taskController = TextEditingController();
  final _taskBox = Hive.box('tasksBox');

@override
  void initState() {
    super.initState();
    _tasks = _taskBox.get('myTasks', defaultValue: <String>[])?.cast<String>() ?? [];
  }

  void _addTask(String task) {
    if (task.trim().isNotEmpty) {
      setState(() {
        _tasks.add(task.trim());
        _taskBox.put('myTasks', _tasks);
      });
      _taskController.clear();
    }
  }

  void _removeTask(int index) {
    setState(() {
      _tasks.removeAt(index);
      _taskBox.put('myTasks', _tasks);
    });
  }

  String _formatTime(int totalSeconds) {
    final minutes = (totalSeconds / 60).floor().toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _taskController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => TimerBloc(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('FlowState Room'),
          centerTitle: true,
          elevation: 0,
        ),
        body: Column(
          children: [
            // Task & Timer
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  // To-Do list
                  Expanded(
                    flex: 1, 
                    child: Container(
                      padding: const EdgeInsets.all(16.0),
                      decoration: const BoxDecoration(
                        border: Border(right: BorderSide(color: Colors.white12)),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            "Session Tasks",
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.grey),
                          ),
                          const SizedBox(height: 16),
                          // Input List
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _taskController,
                                  decoration: const InputDecoration(
                                    hintText: 'Add a task...',
                                    isDense: true,
                                  ),
                                  onSubmitted: (value) => _addTask(value),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add_circle, color: Colors.greenAccent),
                                onPressed: () => _addTask(_taskController.text),
                              )
                            ],
                          ),
                          const SizedBox(height: 16),
                          // The List
                          Expanded(
                            child: ListView.builder(
                              itemCount: _tasks.length,
                              itemBuilder: (context, index) {
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(Icons.radio_button_unchecked, color: Colors.grey, size: 20),
                                  title: Text(_tasks[index]),
                                  onTap: () => _removeTask(index), //removing from the lsit
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // The Timer
                  Expanded(
                    flex: 2, 
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        BlocBuilder<TimerBloc, TimerState>(
                          builder: (context, state) {
                            return Text(
                              _formatTime(state.duration),
                              style: const TextStyle(
                                fontSize: 80, 
                                fontWeight: FontWeight.bold,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 40),
                        
                        BlocBuilder<TimerBloc, TimerState>(
                          builder: (context, state) {
                            final bloc = context.read<TimerBloc>();
                            
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (state is TimerInitial || state is TimerFocusPaused)
                                  FloatingActionButton(
                                    onPressed: () {
                                      if (state is TimerInitial) {
                                        bloc.add(StartFocusTimer());
                                      } else {
                                        bloc.add(ResumeTimer());
                                      }
                                    },
                                    backgroundColor: Colors.greenAccent,
                                    child: const Icon(Icons.play_arrow, color: Colors.black, size: 32),
                                  ),
                                  
                                if (state is TimerFocusInProgress || state is TimerBreakInProgress)
                                  FloatingActionButton(
                                    onPressed: () => bloc.add(PauseTimer()),
                                    backgroundColor: Colors.amber,
                                    child: const Icon(Icons.pause, color: Colors.black, size: 32),
                                  ),

                                const SizedBox(width: 20),
                                
                                ElevatedButton.icon(
                                  onPressed: () => bloc.add(StartBreakTimer()),
                                  icon: const Icon(Icons.coffee),
                                  label: const Text('Take 5'),
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Pressence Tracker
            Expanded(
              flex: 2,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                ),
                child: Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text(
                        "Who's Here",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.grey),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        children: const [
                          ListTile(
                            leading: CircleAvatar(backgroundColor: Colors.green, radius: 6),
                            title: Text('Alex (You)'),
                            trailing: Text('Studying', style: TextStyle(color: Colors.green)),
                          ),
                          ListTile(
                            leading: CircleAvatar(backgroundColor: Colors.amber, radius: 6),
                            title: Text('Mihai'),
                            trailing: Text('On Break', style: TextStyle(color: Colors.amber)),
                          ),
                          ListTile(
                            leading: CircleAvatar(backgroundColor: Colors.grey, radius: 6),
                            title: Text('Sarah'),
                            trailing: Text('Idle', style: TextStyle(color: Colors.grey)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}