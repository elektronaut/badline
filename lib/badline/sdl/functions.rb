# frozen_string_literal: true

module Badline
  module SDL
    INIT_AUDIO = 0x10
    INIT_VIDEO = 0x20
    INIT_GAMECONTROLLER = 0x2000
    INIT_EVENTS = 0x4000

    WINDOWPOS_CENTERED = 0x2fff_0000
    WINDOW_RESIZABLE = 0x20
    RENDERER_ACCELERATED = 0x02
    RENDERER_PRESENTVSYNC = 0x04

    AUDIO_S16SYS = [1].pack("s").getbyte(0) == 1 ? 0x8010 : 0x9010
    AUDIO_ALLOW_FREQUENCY_CHANGE = 0x01

    CONTROLLER_AXIS_LEFTX = 0
    CONTROLLER_AXIS_LEFTY = 1
    CONTROLLER_BUTTON_A = 0
    CONTROLLER_BUTTON_B = 1
    CONTROLLER_BUTTON_X = 2
    CONTROLLER_BUTTON_Y = 3
    CONTROLLER_BUTTON_LEFTSHOULDER = 9
    CONTROLLER_BUTTON_RIGHTSHOULDER = 10
    CONTROLLER_BUTTON_DPAD_UP = 11
    CONTROLLER_BUTTON_DPAD_DOWN = 12
    CONTROLLER_BUTTON_DPAD_LEFT = 13
    CONTROLLER_BUTTON_DPAD_RIGHT = 14

    InitSubSystem = function("SDL_InitSubSystem", [UINT32], INT)
    QuitSubSystem = function("SDL_QuitSubSystem", [UINT32], VOID)
    GetError = function("SDL_GetError", [], STRING)
    SetHint = function("SDL_SetHint", [STRING, STRING], INT)

    CreateWindow = function("SDL_CreateWindow", [STRING, INT, INT, INT, INT, UINT32], POINTER)
    SetWindowTitle = function("SDL_SetWindowTitle", [POINTER, STRING], VOID)
    DestroyWindow = function("SDL_DestroyWindow", [POINTER], VOID)
    GetCurrentDisplayMode = function("SDL_GetCurrentDisplayMode", [INT, POINTER], INT)
    CreateRenderer = function("SDL_CreateRenderer", [POINTER, INT, UINT32], POINTER)
    DestroyRenderer = function("SDL_DestroyRenderer", [POINTER], VOID)
    RenderSetLogicalSize = function("SDL_RenderSetLogicalSize", [POINTER, INT, INT], INT)
    SetRenderDrawColor = function("SDL_SetRenderDrawColor", [POINTER, UINT8, UINT8, UINT8, UINT8], INT)
    RenderClear = function("SDL_RenderClear", [POINTER], INT)
    RenderFillRect = function("SDL_RenderFillRect", [POINTER, POINTER], INT)
    RenderCopy = function("SDL_RenderCopy", [POINTER, POINTER, POINTER, POINTER], INT)
    RenderPresent = function("SDL_RenderPresent", [POINTER], VOID)
    CreateRGBSurfaceFrom = function("SDL_CreateRGBSurfaceFrom",
                                    [POINTER, INT, INT, INT, INT, UINT32, UINT32, UINT32, UINT32], POINTER)
    FreeSurface = function("SDL_FreeSurface", [POINTER], VOID)
    CreateTextureFromSurface = function("SDL_CreateTextureFromSurface", [POINTER, POINTER], POINTER)
    DestroyTexture = function("SDL_DestroyTexture", [POINTER], VOID)

    PollEvent = function("SDL_PollEvent", [POINTER], INT)
    PushEvent = function("SDL_PushEvent", [POINTER], INT)
    GetKeyName = function("SDL_GetKeyName", [INT], STRING)
    SetRelativeMouseMode = function("SDL_SetRelativeMouseMode", [INT], INT)

    NumJoysticks = function("SDL_NumJoysticks", [], INT)
    IsGameController = function("SDL_IsGameController", [INT], INT)
    GameControllerOpen = function("SDL_GameControllerOpen", [INT], POINTER)
    GameControllerName = function("SDL_GameControllerName", [POINTER], STRING)
    GameControllerGetButton = function("SDL_GameControllerGetButton", [POINTER, INT], UINT8)
    GameControllerGetAxis = function("SDL_GameControllerGetAxis", [POINTER, INT], INT16)
    GameControllerClose = function("SDL_GameControllerClose", [POINTER], VOID)

    OpenAudioDevice = function("SDL_OpenAudioDevice", [STRING, INT, POINTER, POINTER, INT], UINT32)
    CloseAudioDevice = function("SDL_CloseAudioDevice", [UINT32], VOID)
    PauseAudioDevice = function("SDL_PauseAudioDevice", [UINT32, INT], VOID)
    QueueAudio = function("SDL_QueueAudio", [UINT32, POINTER, UINT32], INT)
    GetQueuedAudioSize = function("SDL_GetQueuedAudioSize", [UINT32], UINT32)
    ClearQueuedAudio = function("SDL_ClearQueuedAudio", [UINT32], VOID)
  end
end
