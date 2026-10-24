package game

// Web entry points: initialization, per-frame update, and shutdown.
// Called from game_web/main_web.odin's exports, which JavaScript invokes.

import "core:fmt"
import "core:mem"
import "core:os"
import rl "vendor:raylib"

import "dr:data"
import "dr:prefs"
import "dr:render"
import "dr:sim"
import "dr:sim/lifecycle"

// Web-specific state that persists between updates
@(private="file")
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

@(private="file")
web_state: Web_State

// Called once at startup. Initializes raylib, loads assets, sets up
// the renderer and game state.
game_init_web :: proc() {
	when ODIN_OS != .JS {
		fmt.eprintln("game_init_web: only call on web builds")
		return
	}

	// Static plugins: no library loading on web. sim.register_all() will
	// register what was imported (all_plugins_no_netplay).
	sim.register_all()

	// Default preferences, no saved state on web for now (would need IDBFS)
	web_state.ps = Prefs_State{saved = prefs.defaults(), launch = {}, launch_mods = {}}

	// Assets bundled with emscripten's --preload-file
	root := "assets"
	web_state.defs, _ = data.assets_defs_load(root)
	data.extra_defs_load(&web_state.defs)
	data.plugins_digest()

	if len(web_state.defs.levels) == 0 {
		fmt.eprintfln("no level definitions -- assets missing?")
		return
	}

	// Window and audio init
	rl.SetConfigFlags({.VSYNC_HINT, .WINDOW_RESIZABLE})
	rl.InitWindow(render.SCREEN_W * render.WINDOW_SCALE, render.SCREEN_H * render.WINDOW_SCALE, "Deimos Rising")
	rl.InitAudioDevice()

	// Game data structures
	web_state.step_hz = web_state.defs.perm_floats[0x20]
	web_state.step_dt = 1.0 / f64(web_state.step_hz)
	
	render.renderer_init(&web_state.renderer, root, false, true)
	render.effects_init(&web_state.fx)
	
	web_state.state = new(sim.State)
	
	// Main render canvas
	web_state.canvas = rl.LoadRenderTexture(render.SCREEN_W * render.WINDOW_SCALE, render.SCREEN_H * render.WINDOW_SCALE)
	web_state.renderer.canvas = web_state.canvas

	// Flow state machine
	flow_init(&web_state.flow, root, &web_state.defs, web_state.state, &web_state.renderer, &web_state.ps)
	if !flow_launch(&web_state.flow, {}) {
		fmt.eprintln("flow_launch failed")
		return
	}

	rl.SetExitKey(.KEY_NULL) // Escape is pause, not quit

	web_state.initialized = true
	fmt.println("Deimos Rising web initialized")
}

// Called each frame. Returns true to continue, false to exit.
game_update_web :: proc() -> bool {
	when ODIN_OS != .JS {
		return false
	}

	if !web_state.initialized {
		return false
	}

	// Apply preferences
	web_state.renderer.classic = false // Web build always in enhanced mode
	web_state.renderer.textures.mods = prefs_mods(&web_state.ps)
	web_state.renderer.textures.sfx_volume = f32(web_state.ps.saved.sfx_volume) / 100
	web_state.renderer.textures.music_volume = f32(web_state.ps.saved.music_volume) / 100

	// Canvas fit in window
	dst := canvas_fit(web_state.canvas)
	rl.SetMouseOffset(-i32(dst.x), -i32(dst.y))
	rl.SetMouseScale(f32(web_state.renderer.canvas.texture.width) / dst.width, 
	                 f32(web_state.renderer.canvas.texture.height) / dst.height)

	// Input handling
	flow_handle_input(&web_state.flow, &web_state.renderer)

	// Fixed timestep accumulator
	web_state.accumulator += f64(rl.GetFrameTime()) * flow_speed(&web_state.flow, &web_state.renderer)
	for steps := 0; web_state.accumulator >= web_state.step_dt && steps < MAX_STEPS_PER_FRAME; steps += 1 {
		if flow_held(&web_state.flow, &web_state.renderer) {
			web_state.accumulator -= web_state.step_dt
			continue
		}
		flow_step(&web_state.flow, &web_state.renderer, &web_state.fx)
		web_state.accumulator -= web_state.step_dt
	}

	flow_music_update(&web_state.flow, &web_state.renderer)

	// Render to canvas
	rl.BeginTextureMode(web_state.renderer.canvas)
	rl.ClearBackground(rl.Color{0, 0, 0, 255})
	flow_draw(&web_state.flow, &web_state.renderer, &web_state.fx, render.WINDOW_SCALE)
	rl.EndTextureMode()

	// Draw canvas to screen
	rl.BeginDrawing()
	rl.ClearBackground(rl.Color{0, 0, 0, 255})
	whole := dst.width == f32(i32(dst.width / f32(web_state.renderer.canvas.texture.width))) * f32(web_state.renderer.canvas.texture.width)
	rl.SetTextureFilter(web_state.renderer.canvas.texture, whole ? .POINT : .BILINEAR)
	src := rl.Rectangle{0, 0, f32(web_state.renderer.canvas.texture.width), -f32(web_state.renderer.canvas.texture.height)}
	rl.BeginBlendMode(.ALPHA_PREMULTIPLY)
	rl.DrawTexturePro(web_state.renderer.canvas.texture, src, dst, {0, 0}, 0, rl.WHITE)
	rl.EndBlendMode()
	rl.EndDrawing()

	free_all(context.temp_allocator)

	return !web_state.flow.quit
}

// Called on shutdown. Cleans up resources.
game_shutdown_web :: proc() {
	when ODIN_OS != .JS {
		return
	}

	if !web_state.initialized {
		return
	}

	flow_destroy(&web_state.flow)
	render.effects_destroy(&web_state.fx)
	render.renderer_destroy(&web_state.renderer)
	if web_state.state != nil {
		sim.destroy(web_state.state)
		free(web_state.state)
	}
	rl.UnloadRenderTexture(web_state.canvas)
	rl.CloseAudioDevice()
	rl.CloseWindow()

	web_state.initialized = false
	fmt.println("Deimos Rising web shutdown")
}

// Called when the browser window is resized.
game_window_size_changed :: proc(w, h: int) {
	when ODIN_OS != .JS {
		return
	}
	// On web, raylib automatically handles window resizing through emscripten
	// Nothing special needed here as canvas_fit() recalculates each frame
}
