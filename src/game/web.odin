package game

// Web entry points: initialization, per-frame update, and shutdown.
// Called from game_web/main_web.odin's exports, which JavaScript invokes.

import "core:c"
import "core:fmt"
import rl "vendor:raylib"

import "dr:data"
import "dr:prefs"
import "dr:render"
import "dr:sim"

// The browser session. It lives on Shared: a package-level variable would
// be a plugin's own copy (purity, decisions.md D83).
@(private)
Web_State :: struct {
	flow:        Flow,
	renderer:    render.Renderer,
	fx:          render.Effects,
	state:       ^sim.State,
	defs:        sim.Defs,
	ps:          Prefs_State,
	canvas:      rl.RenderTexture2D,
	accumulator: f64,
	step_dt:     f64,
	step_hz:     f32,
	initialized: bool,
}

// Called once at startup. Initializes raylib, loads assets, sets up
// the renderer and game state.
game_init_web :: proc() {
	when ODIN_OS != .JS {
		fmt.eprintln("game_init_web: only call on web builds")
		return
	}

	// Code plugins are linked in (all_plugins_no_netplay). Folders with a
	// plugin.json and no code, Classic Levels among them, are found on the
	// preloaded filesystem.
	declared, problems := data.plugins_discover(data.plugins_roots())
	for p in problems {
		fmt.eprintfln("plugins: %s: %s", p.dir, p.reason)
	}
	sim.plugins_declare(declared)
	sim.register_all()

	// Default preferences, no saved state on web for now (would need IDBFS)
	shared.web.ps = Prefs_State{saved = prefs.defaults(), launch = {}, launch_mods = {}}

	// Assets bundled with emscripten's --preload-file
	root := "assets"
	shared.web.defs, _ = data.assets_defs_load(root)
	data.extra_defs_load(&shared.web.defs)
	data.plugins_digest()

	if len(shared.web.defs.levels) == 0 {
		fmt.eprintfln("no level definitions -- assets missing?")
		return
	}

	// Window and audio init
	rl.SetConfigFlags({.VSYNC_HINT, .WINDOW_RESIZABLE})
	rl.InitWindow(render.SCREEN_W * render.WINDOW_SCALE, render.SCREEN_H * render.WINDOW_SCALE, "Deimos Rising")
	rl.InitAudioDevice()

	// Game data structures
	shared.web.step_hz = shared.web.defs.perm_floats[0x20]
	shared.web.step_dt = 1.0 / f64(shared.web.step_hz)
	
	render.renderer_init(&shared.web.renderer, root, false, true)
	render.effects_init(&shared.web.fx)
	
	shared.web.state = new(sim.State)
	
	// Main render canvas
	shared.web.canvas = rl.LoadRenderTexture(render.SCREEN_W * render.WINDOW_SCALE, render.SCREEN_H * render.WINDOW_SCALE)
	shared.web.renderer.canvas = shared.web.canvas

	// Flow state machine
	flow_init(&shared.web.flow, root, &shared.web.defs, shared.web.state, &shared.web.renderer, &shared.web.ps)
	if !flow_launch(&shared.web.flow, {}) {
		fmt.eprintln("flow_launch failed")
		return
	}

	rl.SetExitKey(.KEY_NULL) // Escape is pause, not quit

	shared.web.initialized = true
	fmt.println("Deimos Rising web initialized")
}

// Called each frame. Returns true to continue, false to exit.
game_update_web :: proc() -> bool {
	when ODIN_OS != .JS {
		return false
	}

	if !shared.web.initialized {
		return false
	}

	// Apply preferences
	shared.web.renderer.classic = false // Web build always in enhanced mode
	shared.web.renderer.textures.mods = prefs_mods(&shared.web.ps)
	shared.web.renderer.textures.sfx_volume = f32(shared.web.ps.saved.sfx_volume) / 100
	shared.web.renderer.textures.music_volume = f32(shared.web.ps.saved.music_volume) / 100

	// Canvas fit in window
	dst := canvas_fit(shared.web.canvas)
	rl.SetMouseOffset(-i32(dst.x), -i32(dst.y))
	rl.SetMouseScale(f32(shared.web.renderer.canvas.texture.width) / dst.width, 
	                 f32(shared.web.renderer.canvas.texture.height) / dst.height)

	// Input handling
	flow_handle_input(&shared.web.flow, &shared.web.renderer)

	// Fixed timestep accumulator
	shared.web.accumulator += f64(rl.GetFrameTime()) * flow_speed(&shared.web.flow, &shared.web.renderer)
	for steps := 0; shared.web.accumulator >= shared.web.step_dt && steps < MAX_STEPS_PER_FRAME; steps += 1 {
		if flow_held(&shared.web.flow, &shared.web.renderer) {
			shared.web.accumulator -= shared.web.step_dt
			continue
		}
		flow_step(&shared.web.flow, &shared.web.renderer, &shared.web.fx)
		shared.web.accumulator -= shared.web.step_dt
	}

	flow_music_update(&shared.web.flow, &shared.web.renderer)

	// Render to canvas
	rl.BeginTextureMode(shared.web.renderer.canvas)
	rl.ClearBackground(rl.Color{0, 0, 0, 255})
	flow_draw(&shared.web.flow, &shared.web.renderer, &shared.web.fx, render.WINDOW_SCALE)
	rl.EndTextureMode()

	// Draw canvas to screen
	rl.BeginDrawing()
	rl.ClearBackground(rl.Color{0, 0, 0, 255})
	whole := dst.width == f32(i32(dst.width / f32(shared.web.renderer.canvas.texture.width))) * f32(shared.web.renderer.canvas.texture.width)
	rl.SetTextureFilter(shared.web.renderer.canvas.texture, whole ? .POINT : .BILINEAR)
	src := rl.Rectangle{0, 0, f32(shared.web.renderer.canvas.texture.width), -f32(shared.web.renderer.canvas.texture.height)}
	rl.BeginBlendMode(.ALPHA_PREMULTIPLY)
	rl.DrawTexturePro(shared.web.renderer.canvas.texture, src, dst, {0, 0}, 0, rl.WHITE)
	rl.EndBlendMode()
	rl.EndDrawing()

	free_all(context.temp_allocator)

	return !shared.web.flow.quit
}

// Called on shutdown. Cleans up resources.
game_shutdown_web :: proc() {
	when ODIN_OS != .JS {
		return
	}

	if !shared.web.initialized {
		return
	}

	flow_destroy(&shared.web.flow)
	render.effects_destroy(&shared.web.fx)
	render.renderer_destroy(&shared.web.renderer)
	if shared.web.state != nil {
		sim.destroy(shared.web.state)
		free(shared.web.state)
	}
	rl.UnloadRenderTexture(shared.web.canvas)
	rl.CloseAudioDevice()
	rl.CloseWindow()

	shared.web.initialized = false
	fmt.println("Deimos Rising web shutdown")
}

// Called when the browser window is resized.
game_window_size_changed :: proc(w, h: int) {
	when ODIN_OS != .JS {
		return
	}
	// The canvas is the window. canvas_fit reads its size each frame.
	rl.SetWindowSize(c.int(w), c.int(h))
}
