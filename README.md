# ☄️ spr
Springs are a powerful model for describing fluid, physically-based animations.
**spr** is a spring-based motion library for Roblox.

```lua
local spr = require(game.ReplicatedStorage.spr)

spr.target(part, 0.5, 2, {
    CFrame = CFrame.new(0, 10, 0)
})
```

## Features
#### A small, easy-to-use API
- spr is easy enough for designers and learning programmers to understand.
- spr only needs a target value and motion parameters. It handles all other aspects of animation automatically.

#### Easy-to-tune motion
- Motion is defined by *frequency* and *damping ratio*.
- Frequency and damping ratio are easy to visualize without running the game. Tuning usually only takes one try.

#### A robust spring model
- spr's robust analytical motion solver handles a wide variety of spring parameters that cause other spring solvers to fail.
- If spr is given a nonconverging set of motion parameters, it will throw a clear error describing what is wrong and how to fix it.

#### Tight integration with Roblox datatypes
- spr animates directly over Roblox properties without additional layers of indirection.
- spr performs runtime type checking, providing stronger typing than Roblox instance property setters.
- spr knows how to animate in the ideal space for each datatype.
    - For example, spr will automatically animate [Color3](https://developer.roblox.com/en-us/api-reference/datatype/Color3) values in perceptually-uniform [CIELUV space.](https://en.wikipedia.org/wiki/CIELUV)

## Spring fundamentals

Damping ratio and undamped frequency are the two properties describing a spring's motion.

- [Damping ratio](https://en.wikipedia.org/wiki/Damping_ratio) describes shape
- [Undamped frequency](https://ocw.mit.edu/courses/mathematics/18-03-differential-equations-spring-2010/readings/supp_notes/MIT18_03S10_chapter_13.pdf) describes speed

### Damping ratio
- **Damping ratio < 1** overshoots and converges on the target. This is called underdamping.
- **Damping ratio = 1** converges on the target without overshooting. This is called critical damping.
- **Damping ratio > 1** converges on the target without overshooting, but slower. This is called overdamping.

Critical damping is recommended as the most visually neutral option with no overshoot.
Underdamping is recommended for animations that need extra pop.

Damping ratio and frequency can be [visualized here.](https://www.desmos.com/calculator/rzvw27ljh9)

## API

### `spr.target`
```lua
spr.target(
   Instance obj,
   number dampingRatio,
   number undampedFrequency,
   table<string, any> targetProperties)
```

Animates the given properties towardes the target values, given damping ratio and frequency values.

#### Examples

```lua
-- damping ratio 1 (critically damped), frequency 4
-- frame quickly moves to the middle of the screen without overshooting
spr.target(frame, 1, 4, {
    Position = UDim2.fromScale(0.5, 0.5)
})
```

```lua
-- damping ratio 1 (critically damped), frequency 1
-- frame slowly moves to the middle of the screen without overshooting
spr.target(frame, 1, 1, {
    Position = UDim2.fromScale(0.5, 0.5)
})
```

```lua
-- damping ratio 0.6 (underdamped), frequency 4
-- frame quickly moves to the middle of the screen, overshoots, and wobbles around the target
spr.target(frame, 0.6, 4, {
    Position = UDim2.fromScale(0.5, 0.5)
})
```

```lua
-- damping ratio 0.6 (underdamped), frequency 1
-- frame slowly moves to the middle of the screen, overshoots, and wobbles around the target
spr.target(frame, 0.6, 1, {
    Position = UDim2.fromScale(0.5, 0.5)
})
```

### `spr.stop`
```lua
spr.stop(
   Instance obj[,
   string property])
```

Stops animations for a particular property.
If a property is not specified, all properties belonging to the instance will stop animating.

#### Examples
```lua
spr.target(frame, 0.6, 1, {
    Position = UDim2.fromScale(1, 1)
})
-- spr is now animating frame.Position

wait(1)

spr.stop(frame, "Position")
-- spr is no longer animating frame.Position
```


```lua
spr.target(frame, 0.6, 1, {
    Position = UDim2.fromScale(1, 1),
    Size = UDim2.fromScale(0.5, 0.5)
})
-- spr is now animating Position and Size

wait(1)

spr.stop(frame)
-- spr is no longer animating Position or Size
```

## Type support

spr supports a subset of Roblox and native Luau types for which interpolation makes sense.
Currently, those are:

- `boolean`
- `CFrame`
- `Color3`
- `ColorSequence`
- `number`
- `NumberRange`
- `UDim`
- `UDim2`
- `Vector2`
- `Vector3`

## Setup

spr is a single-module library.

1. Paste the source of [spr.lua](https://raw.githubusercontent.com/Fraktality/spr/master/spr.lua) into a new ModuleScript
2. Require the ModuleScript with `local spr = require(<path to spr>)`
3. Follow the above code examples to get started with the API.

Documentation on how to use ModuleScripts can be found [here.](https://developer.roblox.com/en-us/api-reference/class/ModuleScript)
