const std = @import("std");
const SimpleRenderer = @import("simple_renderer.zig");
const Types = @import("./types.zig");
const Systems = @import("./systems.zig");
const ecs = @import("ecs");
const Input = @import("./input.zig");
const mem = std.mem;
const rand = std.rand;
const ArrayList = std.ArrayList;

pub const CANVAS_SIZE = 160;
pub const SNAKE_SIZE = 8;

const SNAKE_HALF_SIZE = SNAKE_SIZE / 2;

const PositionComponent = Vec2;

pub const FrameInput = Types.FrameInput;
pub const FruitTag = Types.FruitTag;
pub const GameEvents = Types.GameEvents;
pub const Vec2 = Types.Vec2;
pub const Direction = Types.Direction;
pub const Bounds = Types.Bounds;
pub const SnakeEdges = Types.SnakeEdges;
pub const SegmentComponent = Types.SegmentComponent;
pub const GameState = Types.GameState;
pub const HeadDirection = Types.HeadDirection;
pub const RandomGenerators = Types.RandomGenerators;
pub const SnakeGame = Types.SnakeGame;

pub const StateSetup = struct {
    y_min: u8,
    y_max: u8,
    x_min: u8,
    x_max: u8,
    step_stride: u32,
    random: rand.Random,
};

pub const State = struct {
    allocator: mem.Allocator,
    registery: ecs.Registry,

    fn render(self: *State, renderer: *SimpleRenderer) void {
        _ = self;
        renderer.setForegroundPallete(0);
        renderer.reset();

        renderer.setForegroundPallete(3);
        renderer.drawRect(0, 0, CANVAS_SIZE, 16);
        renderer.setBackgroundPallete(0);
        renderer.drawText("SOKOL Znake", 34, 4);
    }

    pub fn update(self: *State, input: *Input, renderer: *SimpleRenderer) void {
        var existing_input = self.registery.singletons().getOrAdd(FrameInput);
        const old_input = existing_input.*;
        existing_input.* = FrameInput{
            .frame = old_input.frame + 1,
            .input = input.*,
        };
        var events = &self.registery.singletons().get(SnakeGame).events;
        events.clear();
        self.registery.singletons().get(SnakeGame).events.clear();
        self.updateGame();
        self.render(renderer);
        input.swap();

        const snake_game = self.registery.singletons().getConst(SnakeGame);
        switch (snake_game.game_state) {
            .Menu => mainMenu(self, renderer),
            .Play => play(self, renderer),
            .GameOver => gameOver(self, renderer),
        }
    }

    pub fn updateGame(self: *State) void {
        const snake_game = self.registery.singletons().get(SnakeGame);
        switch (snake_game.game_state) {
            .GameOver, .Menu => {
                menuStageInput(&self.registery);
                if (snake_game.events.hasNextStage()) {
                    cleanupSnakeSystem(&self.registery);
                    createSnakeSystem(&self.registery);
                    fruitGenerationSystem(&self.registery);
                }
            },
            .Play => {
                inputSystem(&self.registery);
                if (self.shouldTick()) {
                    self.registery.singletons().get(SnakeGame).events.ticked();
                    headDirectionChangeSystem(&self.registery);

                    collideSystems(&self.registery);
                    if (self.registery.singletons().get(SnakeGame).events.hasDied()) {
                        self.registery.singletons().get(SnakeGame).game_state = .GameOver;
                    }

                    maybeEatFruitSystem(&self.registery);
                    growTailSystem(&self.registery);
                    updateSegmentPositionSystem(&self.registery);
                    fruitGenerationSystem(&self.registery);
                }
            },
        }
    }

    pub fn allocAndInit(allocator: mem.Allocator, config: StateSetup) *State {
        var state = allocator.create(State) catch @panic("Could not Allocate Game Data");
        const bounds: Bounds = .{
            .y_min = config.y_min,
            .y_max = config.y_max,
            .x_min = config.x_min,
            .x_max = config.x_max,
        };
        const randoms: RandomGenerators = .{
            .fruit_random = config.random,
        };
        const events = GameEvents.init(allocator);

        state.* = .{
            .registery = ecs.Registry.init(allocator),
            .allocator = allocator,
        };
        const snake_game = SnakeGame{
            .step_stride = config.step_stride,
            .bounds = bounds,
            .events = events,
            .randoms = randoms,
            .head_direction = HeadDirection{},
        };
        state.registery.singletons().add(snake_game);
        return state;
    }

    pub fn shouldTick(self: *State) bool {
        const frame_data = self.registery.singletons().getConst(FrameInput);
        const snake_game = self.registery.singletons().getConst(SnakeGame);
        return @mod(frame_data.frame, snake_game.step_stride) == 0;
    }

    pub fn snakeHeadPosition(self: *State) *PositionComponent {
        var head = self.registery.singletons().getConst(SnakeEdges).head;
        var view = self.registery.view(.{PositionComponent}, .{});
        return view.get(head);
    }

    pub fn snakeHeadSegment(self: *State) *SegmentComponent {
        var head = self.registery.singletons().getConst(SnakeEdges).head;
        var view = self.registery.view(.{SegmentComponent}, .{});
        return view.get(head);
    }

    pub fn addTail(self: *State, last: ecs.Entity, direction: Direction, pos: PositionComponent) ecs.Entity {
        var entity = self.registery.create();
        const segment_v2 = SegmentComponent{ .direction = direction, .previous_entity = last, .segment_type = .Tail };
        self.registery.add(entity, segment_v2);
        self.registery.add(entity, pos);
        {
            var view = self.registery.view(.{SegmentComponent}, .{});
            var segment = view.get(last);
            segment.*.next_entity = entity;
            if (segment.*.segment_type == .Tail) {
                segment.*.segment_type = .Body;
            }
        }
        return entity;
    }
};

pub fn drawSegmentSmallV2(direction: *const Direction, position: *PositionComponent, simple_renderer: *SimpleRenderer) void {
    const dir = direction.to_vec2();
    var x = (position.x * SNAKE_SIZE);
    var y = (position.y * SNAKE_SIZE);

    if (dir.x == 0) {
        x += SNAKE_HALF_SIZE / 2;
    }

    if (dir.y > 0) {
        y += SNAKE_HALF_SIZE;
    }

    if (dir.x > 0) {
        x += SNAKE_HALF_SIZE;
    }

    if (dir.y == 0) {
        y += SNAKE_HALF_SIZE / 2;
    }

    simple_renderer.setForegroundPallete(1);
    simple_renderer.drawRect(x, y, SNAKE_HALF_SIZE, SNAKE_HALF_SIZE);
}

pub fn drawState(registery: *ecs.Registry, simple_renderer: *SimpleRenderer) void {
    {
        var view = registery.view(.{ FruitTag, PositionComponent }, .{});
        var iter = view.iterator();
        while (iter.next()) |entity| {
            var pos = view.getConst(PositionComponent, entity);

            const x = (pos.x * SNAKE_SIZE);
            const y = (pos.y * SNAKE_SIZE);
            simple_renderer.setForegroundPallete(3);
            simple_renderer.drawRect(x + SNAKE_HALF_SIZE / 2, y + SNAKE_HALF_SIZE / 2, SNAKE_HALF_SIZE, SNAKE_HALF_SIZE);
        }
    }
    {
        var view = registery.view(.{ SegmentComponent, PositionComponent }, .{});
        var iter = view.iterator();
        while (iter.next()) |entity| {
            var pos = view.get(PositionComponent, entity);
            const segment = view.get(SegmentComponent, entity);

            switch (segment.segment_type) {
                .Tail => drawSegmentSmallV2(&segment.direction, pos, simple_renderer),
                else => {
                    const x = (pos.x * SNAKE_SIZE);
                    const y = (pos.y * SNAKE_SIZE);

                    simple_renderer.setForegroundPallete(1);
                    simple_renderer.drawRect(x, y, SNAKE_SIZE, SNAKE_SIZE);
                },
            }
        }
    }
}

pub fn play(state: *State, simple_renderer: *SimpleRenderer) void {
    const snake_game = state.registery.singletons().get(SnakeGame);
    const tick_happened = snake_game.events.hasTicked();
    const has_eaten = snake_game.events.hasEatenFruit();

    if (tick_happened) {
        if (has_eaten) {
            // Print Sound
        } else {
            // Sound
        }
    }
    drawState(&state.registery, simple_renderer);
}

pub fn gameOver(state: *State, simple_renderer: *SimpleRenderer) void {
    const frame_data = state.registery.singletons().getConst(FrameInput);
    simple_renderer.setForegroundPallete(1);
    simple_renderer.drawText("GAME OVER", 42, CANVAS_SIZE - 15);

    if (frame_data.input.down(Input.ButtonB)) {
        simple_renderer.setForegroundPallete(2);
        simple_renderer.drawText("Press Z to Restart", 8, CANVAS_SIZE - 30);
    } else {
        simple_renderer.setForegroundPallete(3);
        simple_renderer.drawText("Press Z to Restart", 8, CANVAS_SIZE - 30);
    }
}

pub fn mainMenu(state: *State, simple_renderer: *SimpleRenderer) void {
    const frame_data = state.registery.singletons().getConst(FrameInput);
    simple_renderer.drawText("WELCOME!", 48, CANVAS_SIZE / 2);
    if (frame_data.input.down(Input.ButtonB)) {
        simple_renderer.setForegroundPallete(1);
    } else {
        simple_renderer.setForegroundPallete(2);
    }
    simple_renderer.drawText("Press Z to Start", 16, CANVAS_SIZE / 2 + 14);
}

const updateSegmentPositionSystem = Systems.updateSegmentPositionSystem;

fn headDirectionChangeSystem(registery: *ecs.Registry) void {
    var next_direction = &registery.singletons().get(SnakeGame).head_direction;
    var head = registery.singletons().getConst(SnakeEdges).head;
    var view = registery.view(.{SegmentComponent}, .{});
    view.get(head).go(next_direction.direction);
    next_direction.swap();
}

fn cleanupSnakeSystem(registery: *ecs.Registry) void {
    var view = registery.view(.{ SegmentComponent, PositionComponent }, .{});
    var iter = view.iterator();
    while (iter.next()) |entity| {
        registery.destroy(entity);
    }
    registery.singletons().remove(SnakeEdges);
}

pub fn fruitGenerationSystem(registery: *ecs.Registry) void {
    if (willCollide(registery)) return;
    var view = registery.view(.{ PositionComponent, FruitTag }, .{});
    if (view.registry.len(FruitTag) > 0) return;

    const snake_game = registery.singletons().getConst(SnakeGame);
    const bounds = snake_game.bounds;
    const fruit_random = snake_game.randoms.fruit_random;

    var entity = registery.create();
    const position: PositionComponent = Vec2{
        .x = fruit_random.intRangeLessThan(i32, bounds.x_min, bounds.x_max),
        .y = fruit_random.intRangeLessThan(i32, bounds.y_min + 1, bounds.y_max),
    };
    registery.add(entity, FruitTag{});
    registery.add(entity, position);
}

pub fn collideSystems(registery: *ecs.Registry) void {
    if (!willCollide(registery)) {
        return;
    }
    registery.singletons().get(SnakeGame).events.died();
}

pub fn createSnakeSystem(registery: *ecs.Registry) void {
    var snake_game = registery.singletons().get(SnakeGame);
    snake_game.head_direction.direction = .Up;
    snake_game.game_state = .Play;

    const bounds = snake_game.bounds;
    const x = @divTrunc((bounds.x_max - bounds.x_min), 2) - 1;
    const y = @divTrunc((bounds.y_max - bounds.y_min), 2) - 1;
    const head_direction = snake_game.head_direction.direction;
    const head_position = Vec2{ .x = x, .y = y };

    var head_entity = createHead(registery, head_direction, head_position);
    var tail_entity = appendTail(registery, head_entity);
    const snake_edges = registery.singletons().getOrAdd(SnakeEdges);
    snake_edges.head = head_entity;
    snake_edges.tail = tail_entity;
}

pub fn inputSystem(registery: *ecs.Registry) void {
    const frame_data = registery.singletons().getConst(FrameInput);
    var next_direction = &registery.singletons().get(SnakeGame).head_direction;
    if (frame_data.input.justPressed(Input.Left)) {
        next_direction.go(.Left);
    }
    if (frame_data.input.justPressed(Input.Right)) {
        next_direction.go(.Right);
    }
    if (frame_data.input.justPressed(Input.Up)) {
        next_direction.go(.Up);
    }
    if (frame_data.input.justPressed(Input.Down)) {
        next_direction.go(.Down);
    }
}

pub fn menuStageInput(registery: *ecs.Registry) void {
    const frame_data = registery.singletons().getConst(FrameInput);
    if (!frame_data.input.justReleased(Input.ButtonB)) return;
    registery.singletons().get(SnakeGame).events.nextStage();
    registery.singletons().get(SnakeGame).events.reseed();
}

pub fn getHeadPosition(registery: *ecs.Registry) PositionComponent {
    var head = registery.singletons().getConst(SnakeEdges).head;
    var view = registery.view(.{PositionComponent}, .{});
    return view.getConst(head);
}

pub fn maybeEatFruitSystem(registery: *ecs.Registry) void {
    var snake_head_position = getHeadPosition(registery);
    var view = registery.view(.{ PositionComponent, FruitTag }, .{});
    var iter = view.iterator();
    while (iter.next()) |entity| {
        const position = view.getConst(PositionComponent, entity);
        if (position.equals(snake_head_position)) {
            registery.removeAll(entity);
            registery.singletons().get(SnakeGame).events.eatFruit();
        }
    }
}

const willCollide = Systems.willCollide;
const appendTail = Systems.appendTail;
const growTailSystem = Systems.growTailSystem;
const createHead = Systems.createHead;
