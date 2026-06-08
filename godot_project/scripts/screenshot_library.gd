extends Node

var _loading_layer: CanvasLayer = null
var _loading_texture_rect: TextureRect = null
var _screenshot_library: Array[String] = []
var _current_index: int = 0

func _ready() -> void:
    print("[VERBATIM] ", Time.get_datetime_string_from_system(), " ENTER _ready (screenshot_library)")
    _init_library()
    _show_loading_screen()
    await get_tree().create_timer(2.0).timeout
    _hide_loading_screen()
    print("[VERBATIM] ", Time.get_datetime_string_from_system(), " EXIT _ready (screenshot_library)")

func _init_library() -> void:
    print("[VERBATIM] ", Time.get_datetime_string_from_system(), " ENTER _init_library")
    # Ensure screenshots directory exists using static methods
    if not DirAccess.dir_exists_absolute("user://screenshots"):
        var err = DirAccess.make_dir_recursive_absolute("user://screenshots")
        if err == OK:
            print("[VERBATIM] Screenshots directory created")
        else:
            print("[VERBATIM] ERROR: Could not create screenshots directory: ", err)
            return
    var dir = DirAccess.open("user://screenshots")
    if dir == null:
        print("[VERBATIM] ERROR: Cannot open screenshots directory")
        return
    dir.list_dir_begin()
    var file: String = dir.get_next()
    while file != "":
        if not file.begins_with(".") and file.ends_with(".png"):
            _screenshot_library.append("user://screenshots/" + file)
        file = dir.get_next()
    dir.list_dir_end()
    _screenshot_library.sort()
    print("[VERBATIM] Screenshot library loaded: ", _screenshot_library.size())
    print("[VERBATIM] EXIT _init_library")

func _show_loading_screen() -> void:
    print("[VERBATIM] ", Time.get_datetime_string_from_system(), " ENTER _show_loading_screen")
    if _loading_layer:
        _loading_layer.queue_free()
    _loading_layer = CanvasLayer.new()
    _loading_layer.layer = 128
    _loading_texture_rect = TextureRect.new()
    _loading_texture_rect.anchor_right = 1.0
    _loading_texture_rect.anchor_bottom = 1.0
    _loading_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    if _screenshot_library.is_empty():
        var placeholder: ColorRect = ColorRect.new()
        placeholder.color = Color(0,0,0)
        var label: Label = Label.new()
        label.text = "No screenshots yet. Fly and screenshots will appear here." 
        label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        label.add_theme_color_override("font_color", Color.WHITE)
        placeholder.add_child(label)
        _loading_layer.add_child(placeholder)
    else:
        var tex: Texture2D = ResourceLoader.load(_screenshot_library[_current_index])
        if tex:
            _loading_texture_rect.texture = tex
            _loading_layer.add_child(_loading_texture_rect)
        else:
            print("[VERBATIM] Failed to load screenshot: ", _screenshot_library[_current_index])
    get_tree().root.add_child.call_deferred(_loading_layer)
    print("[VERBATIM] EXIT _show_loading_screen")

func _hide_loading_screen() -> void:
    print("[VERBATIM] ", Time.get_datetime_string_from_system(), " ENTER _hide_loading_screen")
    if _loading_layer:
        _loading_layer.queue_free()
        _loading_layer = null
        _loading_texture_rect = null
    print("[VERBATIM] EXIT _hide_loading_screen")

func cycle_screenshot() -> void:
    print("[VERBATIM] ", Time.get_datetime_string_from_system(), " ENTER cycle_screenshot")
    if _screenshot_library.is_empty():
        print("[VERBATIM] EXIT cycle_screenshot early=empty")
        return
    _current_index = (_current_index + 1) % _screenshot_library.size()
    if _loading_layer and _loading_texture_rect:
        var tex: Texture2D = ResourceLoader.load(_screenshot_library[_current_index])
        if tex:
            _loading_texture_rect.texture = tex
            print("[VERBATIM] Loading screen updated to index ", _current_index) 
    print("[VERBATIM] EXIT cycle_screenshot ok new_index=", _current_index)

func save_flight_screenshot() -> void:
    print("[VERBATIM] ", Time.get_datetime_string_from_system(), " ENTER save_flight_screenshot")
    var viewport: Viewport = get_viewport()
    if not viewport:
        print("[VERBATIM] EXIT save_flight_screenshot early=no_viewport")
        return
    var img: Image = viewport.get_texture().get_image()
    if not img:
        print("[VERBATIM] EXIT save_flight_screenshot early=no_image")
        return
    var timestamp: String = Time.get_datetime_string_from_system().replace(":", "").replace("-", "")
    var path: String = "user://screenshots/flight_" + timestamp + ".png"
    var err: Error = img.save_png(path)
    if err == OK:
        if not _screenshot_library.has(path):
            _screenshot_library.append(path)
            _screenshot_library.sort()
            print("[VERBATIM] Screenshot saved and added to library: ", path)
        else:
            print("[VERBATIM] Screenshot saved (already in library): ", path)
    else:
        print("[VERBATIM] ERROR saving screenshot: ", err)
    print("[VERBATIM] EXIT save_flight_screenshot ok")

func _input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_L:
            cycle_screenshot()