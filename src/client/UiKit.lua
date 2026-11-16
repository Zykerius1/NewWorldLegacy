--[[
    UiKit — small helpers for building the interface in code.

    Nothing in this project is a hand-built Studio asset: Rojo syncs code only,
    so every frame, label and button the player sees is created here with
    Instance.new. This module keeps that repetitive work in one place.
]]

local UiKit = {}

UiKit.Theme = {
    background = Color3.fromRGB(14, 14, 17),
    panel = Color3.fromRGB(26, 26, 32),
    panelAlt = Color3.fromRGB(38, 38, 46),
    accent = Color3.fromRGB(198, 166, 106), -- brass
    text = Color3.fromRGB(233, 230, 223),
    textDim = Color3.fromRGB(148, 144, 136),
    good = Color3.fromRGB(126, 176, 126),
    bad = Color3.fromRGB(196, 100, 90),
    healthFill = Color3.fromRGB(160, 66, 62),
    expFill = Color3.fromRGB(112, 142, 182),
}

UiKit.FontProse = Enum.Font.Garamond
UiKit.FontUi = Enum.Font.SourceSans
UiKit.FontNumber = Enum.Font.Code

--- Create an instance and set properties in one call.
function UiKit.create(className, props, parent)
    local instance = Instance.new(className)
    for key, value in pairs(props or {}) do
        instance[key] = value
    end
    if parent then
        instance.Parent = parent
    end
    return instance
end

--- A rounded panel with optional padding.
function UiKit.panel(parent, props, padding)
    if not props then
        props = {}
    end
    props.BackgroundColor3 = props.BackgroundColor3 or UiKit.Theme.panel
    props.BorderSizePixel = 0
    local frame = UiKit.create("Frame", props, parent)
    UiKit.create("UICorner", { CornerRadius = UDim.new(0, 6) }, frame)
    if padding then
        UiKit.create("UIPadding", {
            PaddingTop = UDim.new(0, padding),
            PaddingBottom = UDim.new(0, padding),
            PaddingLeft = UDim.new(0, padding),
            PaddingRight = UDim.new(0, padding),
        }, frame)
    end
    return frame
end

--- A text label with sensible defaults.
function UiKit.label(parent, props)
    local options = {
        BackgroundTransparency = 1,
        Font = UiKit.FontProse,
        TextColor3 = UiKit.Theme.text,
        TextSize = 16,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        TextWrapped = false,
    }
    for key, value in pairs(props or {}) do
        options[key] = value
    end
    local label = UiKit.create("TextLabel", options, parent)
    return label
end

--- A button with a hover/press response, because a plain TextButton reads as
--- dead on a dark background.
function UiKit.button(parent, props, onClick)
    local options = {
        BackgroundColor3 = UiKit.Theme.panelAlt,
        BorderSizePixel = 0,
        AutoButtonColor = true,
        Font = UiKit.FontUi,
        TextColor3 = UiKit.Theme.text,
        TextSize = 16,
        TextWrapped = true,
    }
    for key, value in pairs(props or {}) do
        options[key] = value
    end
    local button = UiKit.create("TextButton", options, parent)
    UiKit.create("UICorner", { CornerRadius = UDim.new(0, 5) }, button)
    UiKit.create("UIPadding", {
        PaddingLeft = UDim.new(0, 8),
        PaddingRight = UDim.new(0, 8),
    }, button)
    if onClick then
        button.Activated:Connect(onClick)
    end
    return button
end

--- A labelled horizontal bar. Returns the frame plus a set(fraction) function.
function UiKit.bar(parent, props, fillColor)
    local options = {
        BackgroundColor3 = Color3.fromRGB(12, 12, 15),
        BorderSizePixel = 0,
    }
    for key, value in pairs(props or {}) do
        options[key] = value
    end
    local track = UiKit.create("Frame", options, parent)
    UiKit.create("UICorner", { CornerRadius = UDim.new(1, 0) }, track)
    local fill = UiKit.create("Frame", {
        BackgroundColor3 = fillColor,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 1, 0),
    }, track)
    UiKit.create("UICorner", { CornerRadius = UDim.new(1, 0) }, fill)

    return track, function(fraction)
        fill.Size = UDim2.new(math.clamp(fraction, 0, 1), 0, 1, 0)
    end
end

--- Objects that describe HOW a frame is laid out, not what is in it. A frame is
--- built once with its layout attached, then re-rendered many times; destroying
--- the layout on the first clear leaves every row stacked on top of the last,
--- which is exactly what a screen full of overlapping text looks like.
local STRUCTURAL = {
    UIListLayout = true,
    UIGridLayout = true,
    UITableLayout = true,
    UIPageLayout = true,
    UIPadding = true,
    UICorner = true,
    UIStroke = true,
    UIAspectRatioConstraint = true,
    UISizeConstraint = true,
}

--- Remove every child, so a frame can be re-rendered from scratch — keeping the
--- layout and padding objects that were attached to it when it was built.
function UiKit.clear(instance)
    for _, child in ipairs(instance:GetChildren()) do
        if not STRUCTURAL[child.ClassName] then
            child:Destroy()
        end
    end
end

--- The frame's vertical stack, creating it only if it is not already there.
--- Frames survive re-rendering and clear() keeps their layout, so adding one
--- unconditionally would leave a second UIListLayout behind on every render.
function UiKit.ensureStack(parent, padding)
    for _, child in ipairs(parent:GetChildren()) do
        if child:IsA("UIListLayout") then
            return child
        end
    end
    return UiKit.stack(parent, padding)
end

--- A vertical stack layout helper.
function UiKit.stack(parent, padding)
    return UiKit.create("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, padding or 6),
    }, parent)
end

return UiKit
