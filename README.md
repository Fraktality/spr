# ☄️ spr

Springs are powerful approach for describing fluid, physically-based animation.<br/>
**spr** is a high-performance and user-friendly motion library for Roblox based on springs.

Animations are a single line of code:

```lua
spr.target(part, springDamping, springFrequency, { CFrame = CFrame.new(0, 10, 0) })
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

## API

### `spr.target`
```lua
spr.target(
   obj: Instance,
   dampingRatio: number,
   undampedFrequency: number,
   targetProperties: {[string]: any})
```

Animates the given properties towardes the target values.

### `spr.completed`
```lua
spr.completed(obj: Instance, callback: ()->())
```

Registers a callback function that will be called the next time the instance stops animating. The callback is only called once.
This is useful for tracking instance lifetime, such as destroying a part when it becomes invisible.

### `spr.stop`
```lua
spr.stop(obj: Instance, property: string?)
```

Stops animations for a particular property.
If a property is not specified, all properties belonging to the instance will stop animating.
Any completed callbacks associated with the instance will be canceled.

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
3. Follow the below code examples to get started with the API.

Documentation on how to use ModuleScripts can be found [here.](https://developer.roblox.com/en-us/api-reference/class/ModuleScript)

## Examples

### `spr.target`

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

### `spr.completed`

```lua
spr.target(workspace.Part, 1, 1, {Transparency = 1})
spr.completed(workspace.Part, function() workspace.Part:Destroy() end)
```

### `spr.stop`

```lua
spr.target(frame, 0.6, 1, {
    Position = UDim2.fromScale(1, 1)
})
-- spr is now animating frame.Position

task.wait(1)

spr.stop(frame, "Position")
-- spr is no longer animating frame.Position
```


```lua
spr.target(frame, 0.6, 1, {
    Position = UDim2.fromScale(1, 1),
    Size = UDim2.fromScale(0.5, 0.5)
})
-- spr is now animating Position and Size

task.wait(1)

spr.stop(frame)
-- spr is no longer animating Position or Size
```
