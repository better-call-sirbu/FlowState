import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive/hive.dart';
import '../blocs/timer_bloc.dart';

class StudyRoomScreen extends StatefulWidget {
  const StudyRoomScreen({super.key});

  @override
  State<StudyRoomScreen> createState() => _StudyRoomScreenState();
}

class _StudyRoomScreenState extends State<StudyRoomScreen> {
  // To-Do list
  List<String> _tasks = [];
  final TextEditingController _taskController = TextEditingController();
  final _taskBox = Hive.box('tasksBox'); 

  // Timer SetUp
  final TextEditingController _totalMinCtrl = TextEditingController(text: "120");
  final TextEditingController _totalSecCtrl = TextEditingController(text: "0");
  
  final TextEditingController _sessionMinCtrl = TextEditingController(text: "30");
  final TextEditingController _sessionSecCtrl = TextEditingController(text: "0");
  
  final TextEditingController _breakMinCtrl = TextEditingController(text: "10");
  final TextEditingController _breakSecCtrl = TextEditingController(text: "0");

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
    final hours = (totalSeconds / 3600).floor().toString().padLeft(2, '0');
    final minutes = ((totalSeconds % 3600) / 60).floor().toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return hours == '00' ? '$minutes:$seconds' : '$hours:$minutes:$seconds';
  }

  @override
  void dispose() {
    _taskController.dispose();
    _totalMinCtrl.dispose();
    _totalSecCtrl.dispose();
    _sessionMinCtrl.dispose();
    _sessionSecCtrl.dispose();
    _breakMinCtrl.dispose();
    _breakSecCtrl.dispose();
    super.dispose();
  }

  Widget _buildTimeInputRow(String label, TextEditingController minCtrl, TextEditingController secCtrl) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 150,
            child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          SizedBox(
            width: 60,
            child: TextField(
              controller: minCtrl,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              decoration: const InputDecoration(labelText: "Min", border: OutlineInputBorder()),
            ),
          ),
          const SizedBox(width: 10),
          const Text(":", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(width: 10),
          SizedBox(
            width: 60,
            child: TextField(
              controller: secCtrl,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              decoration: const InputDecoration(labelText: "Sec", border: OutlineInputBorder()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSetupUI(BuildContext context, TimerBloc bloc) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("Session Setup", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 30),
            
            _buildTimeInputRow("Total Grind Time", _totalMinCtrl, _totalSecCtrl),
            _buildTimeInputRow("Focus Block", _sessionMinCtrl, _sessionSecCtrl),
            _buildTimeInputRow("Break Length", _breakMinCtrl, _breakSecCtrl),
            
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () {
                int totalSecs = (int.tryParse(_totalMinCtrl.text) ?? 0) * 60 + (int.tryParse(_totalSecCtrl.text) ?? 0);
                int sessionSecs = (int.tryParse(_sessionMinCtrl.text) ?? 0) * 60 + (int.tryParse(_sessionSecCtrl.text) ?? 0);
                int breakSecs = (int.tryParse(_breakMinCtrl.text) ?? 0) * 60 + (int.tryParse(_breakSecCtrl.text) ?? 0);

                bloc.add(StartSession(
                  totalStudySeconds: totalSecs,
                  sessionSeconds: sessionSecs,
                  breakSeconds: breakSecs,
                ));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
              ),
              child: const Text('START SESSION', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5)),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildActiveUI(BuildContext context, TimerState state, TimerBloc bloc) {
    if (state is TimerComplete) {
      return const Center(
        child: Text("SESSION COMPLETE! 🎉", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.greenAccent)),
      );
    }

    int currentDuration = 0;
    int accumulated = 0;
    int totalTarget = 1;
    bool isBreak = false;
    bool isPaused = state is TimerPaused;

    if (state is TimerActive) {
      currentDuration = state.currentDuration;
      accumulated = state.accumulatedStudy;
      totalTarget = state.totalStudyTarget;
      isBreak = state.isBreak;
    } else if (state is TimerPaused) {
      currentDuration = state.currentDuration;
      accumulated = state.accumulatedStudy;
      totalTarget = state.totalStudyTarget;
      isBreak = state.isBreak;
    }

    // Prevent divide by zero error if user enters 0 for total time
    double progress = totalTarget > 0 ? (accumulated / totalTarget) : 0;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          isBreak ? "☕ BREAK TIME" : "🧠 FOCUSING",
          style: TextStyle(
            fontSize: 20, 
            fontWeight: FontWeight.w800, 
            letterSpacing: 2,
            color: isBreak ? Colors.amber : Colors.greenAccent,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _formatTime(currentDuration),
          style: const TextStyle(
            fontSize: 90, 
            fontWeight: FontWeight.bold,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 20),
        
        // The Master Progress Bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 80.0),
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: Colors.white12,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                "Total Progress: ${_formatTime(accumulated)} / ${_formatTime(totalTarget)}",
                style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 40),
        FloatingActionButton(
          onPressed: () => isPaused ? bloc.add(ResumeTimer()) : bloc.add(PauseTimer()),
          backgroundColor: isPaused ? Colors.greenAccent : Colors.white,
          child: Icon(isPaused ? Icons.play_arrow : Icons.pause, color: Colors.black, size: 32),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => TimerBloc(),
      child: Scaffold(
        appBar: AppBar(title: const Text('FlowState Room'), centerTitle: true, elevation: 0),
        body: Column(
          children: [
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  // To-Do List UI
                  Expanded(
                    flex: 1,
                    child: Container(
                      padding: const EdgeInsets.all(16.0),
                      decoration: const BoxDecoration(border: Border(right: BorderSide(color: Colors.white12))),
                      child: Column(
                        children: [
                          const Text("Session Tasks", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.grey)),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _taskController,
                                  decoration: const InputDecoration(hintText: 'Add a task...', isDense: true),
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
                          Expanded(
                            child: ListView.builder(
                              itemCount: _tasks.length,
                              itemBuilder: (context, index) {
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(Icons.radio_button_unchecked, color: Colors.grey, size: 20),
                                  title: Text(_tasks[index]),
                                  onTap: () => _removeTask(index), 
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Timer
                  Expanded(
                    flex: 2, 
                    child: BlocBuilder<TimerBloc, TimerState>(
                      builder: (context, state) {
                        final bloc = context.read<TimerBloc>();
                        // Show the Setup screen OR the Running Clock based on state
                        if (state is TimerInitial) {
                          return _buildSetupUI(context, bloc);
                        } else {
                          return _buildActiveUI(context, state, bloc);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),

            // Presence tracker
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
                      child: Text("Who's Here", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.grey)),
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