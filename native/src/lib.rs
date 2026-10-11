#![allow(non_snake_case)]
//! Código nativo do Speedoru (godot-rust): as partes da corrida que rodam a cada passo de física.
//! Cada classe aqui é a base de um script (F1Car extends F1CarCore, BotDriver extends BotDriverCore);
//! o GDScript continua com o resto.
use godot::init::InitStage;
use godot::prelude::*;

mod bot;
mod audio;
mod car;
mod damage;
mod fx;
mod guide;
mod manager;
mod path;
mod race;
mod scenery;
mod surface;
mod util;

struct SpeedoruNative;

#[gdextension]
unsafe impl ExtensionLibrary for SpeedoruNative {
    fn on_stage_deinit(stage: InitStage) {
        if stage == InitStage::MainLoop {
            bot::clear_cache();
        }
    }
}
