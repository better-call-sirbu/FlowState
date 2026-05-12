import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';

// Timer
abstract class TimerEvent {}

class StartSession extends TimerEvent {
  final int totalStudySeconds;
  final int sessionSeconds;
  final int breakSeconds;

  StartSession({
    required this.totalStudySeconds,
    required this.sessionSeconds,
    required this.breakSeconds,
  });
}

class PauseTimer extends TimerEvent {}
class ResumeTimer extends TimerEvent {}
class _TimerTicked extends TimerEvent {}

// UI
abstract class TimerState {}

class TimerInitial extends TimerState {} // Shows the setup screen

class TimerActive extends TimerState {
  final int currentDuration;    // What shows on the massive clock
  final int accumulatedStudy;   // How much focus time is done
  final int totalStudyTarget;   // The master goal
  final bool isBreak;           // True if resting, False if grinding

  TimerActive({
    required this.currentDuration,
    required this.accumulatedStudy,
    required this.totalStudyTarget,
    required this.isBreak,
  });
}

class TimerPaused extends TimerState {
  final int currentDuration;
  final int accumulatedStudy;
  final int totalStudyTarget;
  final bool isBreak;

  TimerPaused({
    required this.currentDuration,
    required this.accumulatedStudy,
    required this.totalStudyTarget,
    required this.isBreak,
  });
}

class TimerComplete extends TimerState {} // The "You Did It" screen

class TimerBloc extends Bloc<TimerEvent, TimerState> {
  StreamSubscription<int>? _tickerSubscription;
  
  // The Settings
  int _totalStudySeconds = 0;
  int _sessionSeconds = 0;
  int _breakSeconds = 0;
  
  // The Live Trackers
  int _currentDuration = 0;
  int _accumulatedStudy = 0;
  bool _isBreak = false;

  TimerBloc() : super(TimerInitial()) {
    on<StartSession>(_onStartSession);
    on<PauseTimer>(_onPauseTimer);
    on<ResumeTimer>(_onResumeTimer);
    on<_TimerTicked>(_onTicked);
  }

  void _onStartSession(StartSession event, Emitter<TimerState> emit) {
    _totalStudySeconds = event.totalStudySeconds;
    
    // Focus higher than total work case
    if (event.sessionSeconds > _totalStudySeconds) {
      _sessionSeconds = _totalStudySeconds;
    } else {
      _sessionSeconds = event.sessionSeconds;
    }
    
    _breakSeconds = event.breakSeconds;
    
    _currentDuration = _sessionSeconds;
    _accumulatedStudy = 0;
    _isBreak = false;

    _startTicker();
    emit(_createActiveState());
  }

  void _onPauseTimer(PauseTimer event, Emitter<TimerState> emit) {
    _tickerSubscription?.pause();
    emit(TimerPaused(
      currentDuration: _currentDuration,
      accumulatedStudy: _accumulatedStudy,
      totalStudyTarget: _totalStudySeconds,
      isBreak: _isBreak,
    ));
  }

  void _onResumeTimer(ResumeTimer event, Emitter<TimerState> emit) {
    _tickerSubscription?.resume();
    emit(_createActiveState());
  }

  void _onTicked(_TimerTicked event, Emitter<TimerState> emit) {
    if (_currentDuration > 0) {
      _currentDuration--;
      
      // Ignore brake time towards total work time
      if (!_isBreak) {
        _accumulatedStudy++;
      }
      emit(_createActiveState());
    } else {
      // Phase switch
      if (!_isBreak) {
        // One focus session finished
        if (_accumulatedStudy >= _totalStudySeconds) {
          _tickerSubscription?.cancel();
          emit(TimerComplete()); // Session compleated
        } else {
          // Brake Start
          _isBreak = true;
          _currentDuration = _breakSeconds;
          emit(_createActiveState());
        }
      } else {
        // Brake end
        _isBreak = false;
        
        // Safety check: final session isn't longer than the time left
        int remainingStudy = _totalStudySeconds - _accumulatedStudy;
        _currentDuration = (remainingStudy < _sessionSeconds) ? remainingStudy : _sessionSeconds;
        
        emit(_createActiveState());
      }
    }
  }

  void _startTicker() {
    _tickerSubscription?.cancel();
    _tickerSubscription = Stream.periodic(const Duration(seconds: 1), (x) => x).listen((_) {
      add(_TimerTicked());
    });
  }

  TimerActive _createActiveState() {
    return TimerActive(
      currentDuration: _currentDuration,
      accumulatedStudy: _accumulatedStudy,
      totalStudyTarget: _totalStudySeconds,
      isBreak: _isBreak,
    );
  }

  @override
  Future<void> close() {
    _tickerSubscription?.cancel();
    return super.close();
  }
}