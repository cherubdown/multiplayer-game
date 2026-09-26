extends Node
## Runs account work (password hashing, database queries) on one background
## thread so a slow hash or query never stalls the game loop. Jobs run one at
## a time in the order they were queued, so the store never sees two at once.
##
##   var err: String = await worker.run(store.register.bind(name, password))

signal _job_finished(id: int, result: Variant)

var _thread := Thread.new()
var _mutex := Mutex.new()
var _semaphore := Semaphore.new()
var _jobs: Array = []  # [id, Callable]
var _stopping := false
var _next_id := 0


func _ready() -> void:
	_thread.start(_loop)


func _exit_tree() -> void:
	stop()


## Runs job on the worker thread and returns its result. Await it.
func run(job: Callable) -> Variant:
	_next_id += 1
	var id := _next_id
	_mutex.lock()
	_jobs.append([id, job])
	_mutex.unlock()
	_semaphore.post()
	while true:
		var finished: Array = await _job_finished
		if finished[0] == id:
			return finished[1]
	return null


## Finishes the queued jobs and joins the thread.
func stop() -> void:
	if not _thread.is_started():
		return
	_mutex.lock()
	_stopping = true
	_mutex.unlock()
	_semaphore.post()
	_thread.wait_to_finish()


func _loop() -> void:
	while true:
		_semaphore.wait()
		_mutex.lock()
		var job: Array = _jobs.pop_front() if not _jobs.is_empty() else []
		var stopping := _stopping
		_mutex.unlock()
		if job.is_empty():
			if stopping:
				return
			continue
		var result: Variant = job[1].call()
		_job_finished.emit.call_deferred(job[0], result)
