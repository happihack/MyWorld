class_name AppLifecycle
extends Node
## Translates OS/window lifecycle notifications into EventBus signals (bible §31.12).
## Lives in the Main scene. Listeners (e.g. SaveManager) react to the signals; this
## node never decides game behaviour itself.
##
## Android: never assume the OS keeps the app alive after app_paused.


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED:
			Log.info(Log.Category.CORE, "Application paused")
			EventBus.app_paused.emit()
		NOTIFICATION_APPLICATION_RESUMED:
			Log.info(Log.Category.CORE, "Application resumed")
			EventBus.app_resumed.emit()
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			Log.debug(Log.Category.CORE, "Focus lost")
			EventBus.app_focus_changed.emit(false)
		NOTIFICATION_APPLICATION_FOCUS_IN:
			Log.debug(Log.Category.CORE, "Focus gained")
			EventBus.app_focus_changed.emit(true)
		NOTIFICATION_WM_CLOSE_REQUEST:
			Log.info(Log.Category.CORE, "Quit requested")
			EventBus.app_quit_requested.emit()
		NOTIFICATION_WM_GO_BACK_REQUEST:
			Log.debug(Log.Category.UI, "Back requested")
			EventBus.back_requested.emit()
