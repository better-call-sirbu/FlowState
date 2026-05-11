import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

// Buttons
abstract class TimerEvent extends Equatable {
  const TimerEvent();

  @override
  List<Object> get props => [];
}

class StartFocusTimer extends TimerEvent {}
class PauseTimer extends TimerEvent {}
class ResumeTimer extends TimerEvent {}
class StartBreakTimer extends TimerEvent {}
class TimerTicked extends TimerEvent {
  final int duration;
  const TimerTicked({required this.duration});

  @override
  List<Object> get props => [duration];
}

// States
abstract class TimerState extends Equatable {
  final int duration; // Seconds remaining
  const TimerState(this.duration);

  @override
  List<Object> get props => [duration];
}

class TimerInitial extends TimerState {
  const TimerInitial(super.duration); 
}
class TimerFocusInProgress extends TimerState {
  const TimerFocusInProgress(super.duration);
}
class TimerFocusPaused extends TimerState {
  const TimerFocusPaused(super.duration);
}
class TimerBreakInProgress extends TimerState {
  const TimerBreakInProgress(super.duration); 
}

// BLOC
class TimerBloc extends Bloc<TimerEvent, TimerState> {
  static const int focusDuration = 1500; 
  static const int breakDuration = 300;  
  
  StreamSubscription<int>? _tickerSubscription;

  TimerBloc() : super(const TimerInitial(focusDuration)) {
    on<StartFocusTimer>(_onStartFocus);
    on<PauseTimer>(_onPause);
    on<ResumeTimer>(_onResume);
    on<StartBreakTimer>(_onStartBreak);
    on<TimerTicked>(_onTicked);
  }

  void _onStartFocus(StartFocusTimer event, Emitter<TimerState> emit) {
    emit(const TimerFocusInProgress(focusDuration));
    _startTicker(focusDuration);
  }

  void _onStartBreak(StartBreakTimer event, Emitter<TimerState> emit) {
    emit(const TimerBreakInProgress(breakDuration));
    _startTicker(breakDuration);
  }

  void _onPause(PauseTimer event, Emitter<TimerState> emit) {
    if (state is TimerFocusInProgress) {
      _tickerSubscription?.pause(); 
      emit(TimerFocusPaused(state.duration));
    }
  }

  void _onResume(ResumeTimer event, Emitter<TimerState> emit) {
    if (state is TimerFocusPaused) {
      _tickerSubscription?.resume();
      emit(TimerFocusInProgress(state.duration));
    }
  }

  void _onTicked(TimerTicked event, Emitter<TimerState> emit) {
    if (event.duration > 0) {
      if (state is TimerFocusInProgress) {
        emit(TimerFocusInProgress(event.duration));
      } else if (state is TimerBreakInProgress) {
        emit(TimerBreakInProgress(event.duration));
      }
    } else {
      _tickerSubscription?.cancel();
      emit(const TimerInitial(focusDuration)); 
    }
  }

  void _startTicker(int duration) {
    _tickerSubscription?.cancel();
    _tickerSubscription = Stream.periodic(const Duration(seconds: 1), (x) => duration - x - 1)
        .take(duration)
        .listen((timeLeft) => add(TimerTicked(duration: timeLeft)));
  }

  @override
  Future<void> close() {
    _tickerSubscription?.cancel(); 
    return super.close();
  }
}