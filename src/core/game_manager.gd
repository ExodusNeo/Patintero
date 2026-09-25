extends Node

# Autoload: GameManager
# Phase 3: Match Flow, Inning Clock & Palarong Pambansa Scoring System

enum MatchState { WAITING, PLAYING, HALFTIME, MATCH_OVER }

signal score_updated(runner_pts: int, defender_pts: int)
signal match_timer_updated(time_left: float)
signal match_state_changed(new_state: MatchState)
signal point_event_triggered(team_name: String, points: int, reason: String)
signal halftime_reached(round_num: int)
signal match_completed(winner_team: String, r_score: int, d_score: int)

var current_state: MatchState = MatchState.PLAYING
var runner_score: int = 0
var defender_score: int = 0

var current_round: int = 1
const MAX_ROUNDS: int = 2
const ROUND_DURATION: float = 120.0 # 2 minutes per inning

var round_time_left: float = 120.0
var is_timer_running: bool = false
var has_warned_30s: bool = false

func _ready() -> void:
	# Connect to NetworkManager tag & foul events for defender scoring
	NetworkManager.player_tagged.connect(_on_network_player_tagged)
	NetworkManager.player_foul.connect(_on_network_player_foul)
	start_match()

func start_match() -> void:
	runner_score = 0
	defender_score = 0
	current_round = 1
	start_round(1)

func start_round(round_num: int) -> void:
	current_round = round_num
	round_time_left = ROUND_DURATION
	is_timer_running = true
	has_warned_30s = false
	current_state = MatchState.PLAYING
	match_state_changed.emit(current_state)
	score_updated.emit(runner_score, defender_score)
	match_timer_updated.emit(round_time_left)
	AudioManager.play_whistle(true)

func _process(delta: float) -> void:
	if not is_timer_running or current_state != MatchState.PLAYING:
		return
	
	round_time_left -= delta
	if round_time_left < 0.0:
		round_time_left = 0.0
	
	match_timer_updated.emit(round_time_left)
	
	# 30-Second Warning
	if round_time_left <= 30.0 and not has_warned_30s:
		has_warned_30s = true
		AudioManager.play_whistle(false)
		point_event_triggered.emit("ALERT", 0, "⏰ 30 SECONDS REMAINING IN THE INNING!")
	
	# Inning Time Up
	if round_time_left <= 0.0:
		is_timer_running = false
		_on_round_timer_expired()

func _on_round_timer_expired() -> void:
	AudioManager.play_foul()
	if current_round < MAX_ROUNDS:
		current_state = MatchState.HALFTIME
		match_state_changed.emit(current_state)
		halftime_reached.emit(current_round)
	else:
		current_state = MatchState.MATCH_OVER
		match_state_changed.emit(current_state)
		var winner := "RUNNERS"
		if defender_score > runner_score:
			winner = "DEFENDERS"
		elif defender_score == runner_score:
			winner = "DRAW / TIE"
		match_completed.emit(winner, runner_score, defender_score)

func add_runner_points(points: int, reason: String) -> void:
	runner_score += points
	score_updated.emit(runner_score, defender_score)
	point_event_triggered.emit("RUNNERS", points, reason)

func add_defender_points(points: int, reason: String) -> void:
	defender_score += points
	score_updated.emit(runner_score, defender_score)
	point_event_triggered.emit("DEFENDERS", points, reason)

func _on_network_player_tagged(_runner_name: String, tagger_name: String) -> void:
	# Palarong Pambansa: Defenders score +5 pts on tag turnover
	add_defender_points(5, "TAYA! %s tagged runner (+5 Defense)" % tagger_name)

func _on_network_player_foul(player_name: String, _reason: String) -> void:
	# Out of bounds foul: +3 pts to defense
	add_defender_points(3, "OUT OF BOUNDS: %s (+3 Defense)" % player_name)

func restart_current_match() -> void:
	start_match()
