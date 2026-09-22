class_name BattleEventAudio
extends Node

## Short procedural prototype cues. Audio responds to accepted simulation events,
## never advances gameplay, and uses the same mute preference as the care scene.
var muted := false
var played_events: Array[String] = []
var _voices: Array[AudioStreamPlayer] = []
var _tones: Dictionary = {}
var _voice_index := 0
const TONES := {"charge_started": [360.0, 600.0, 0.10], "attack_released": [540.0, 210.0, 0.08], "hit": [170.0, 70.0, 0.07], "defense_started": [480.0, 740.0, 0.08], "perfect_guard": [720.0, 1100.0, 0.16], "rush_collision": [130.0, 65.0, 0.09], "item_used": [660.0, 880.0, 0.13]}

func play_event(event: Dictionary) -> void:
	var kind := String(event.get("event", ""))
	if muted or not TONES.has(kind):
		return
	if _voices.is_empty():
		for index: int in 4:
			var voice := AudioStreamPlayer.new()
			voice.volume_db = -23
			add_child(voice)
			_voices.append(voice)
	if not _tones.has(kind):
		_tones[kind] = _tone(TONES[kind])
	var voice: AudioStreamPlayer = _voices[_voice_index % _voices.size()]
	_voice_index += 1
	voice.stream = _tones[kind]
	voice.play()
	played_events.append(kind)
	if played_events.size() > 64:
		played_events.pop_front()

func _tone(parameters: Array) -> AudioStreamWAV:
	var sample_rate := 22050
	var count := roundi(float(parameters[2]) * sample_rate)
	var data := PackedByteArray()
	data.resize(count * 2)
	var phase := 0.0
	for index: int in count:
		var progress := float(index) / count
		phase += TAU * lerpf(float(parameters[0]), float(parameters[1]), progress) / sample_rate
		var envelope := minf(1, progress * 20) * pow(1 - progress, 2)
		var sample := roundi(sin(phase) * envelope * 15000)
		data.encode_s16(index * 2, sample)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.data = data
	return stream

func stop_all() -> void:
	for voice: AudioStreamPlayer in _voices:
		if is_instance_valid(voice):
			voice.stop()
			voice.stream = null

func _exit_tree() -> void:
	stop_all()
