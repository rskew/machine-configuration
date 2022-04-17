import           Graphics.X11.ExtraTypes.XF86
import           System.IO
import           XMonad
import           XMonad.Actions.NoBorders
import           XMonad.Actions.SpawnOn
import           XMonad.Hooks.DynamicLog
import           XMonad.Hooks.EwmhDesktops
import           XMonad.Hooks.ManageDocks
import           XMonad.Hooks.ManageHelpers
import           XMonad.Hooks.SetWMName
import           XMonad.Hooks.UrgencyHook
import           XMonad.Layout.MultiToggle
import           XMonad.Layout.MultiToggle.Instances
import           XMonad.Layout.Spacing
import qualified XMonad.StackSet                     as W
import           XMonad.Util.EZConfig                (additionalKeys, removeKeys)
import           XMonad.Util.Run                     (spawnPipe)

windowGap = 10

myWorkspaces = [ (xK_quoteleft, "~")
               , (xK_1, "1")
               , (xK_2, "2")
               , (xK_3, "3")
               , (xK_4, "4")
               , (xK_5, "5")
               , (xK_6, "6")
               , (xK_7, "7")
               , (xK_8, "8")
               , (xK_9, "9")
               , (xK_0, "0")
               , (xK_minus, "-")
               , (xK_equal, "=")
               , (xK_BackSpace, "←")
               ]

main = do
  xmproc <- spawnPipe "xmobar /home/rowan/machine-configuration/dotfiles/.xmobarrc"
  xmonad $ withUrgencyHook NoUrgencyHook $ docks defaultConfig
      { modMask            = mod1Mask
      , borderWidth        = 1
      , terminal           = "urxvt -cd \"$PWD\""
      , normalBorderColor  = "#000"
      , focusedBorderColor = "#0af"
      , workspaces = map snd myWorkspaces
      , manageHook = mWManager
      , layoutHook = mkToggle (single NBFULL) $ avoidStruts
                                              $ spacingWithEdge windowGap
                                              $ layoutHook defaultConfig
      , handleEventHook = fullscreenEventHook
      , startupHook = do
          setWMName "LG3D"
      , logHook = dynamicLogWithPP xmobarPP
                      { ppOutput = hPutStrLn xmproc
                      --, ppTitle = xmobarColor "green" "" . shorten 0 --50
                      , ppTitle = xmobarColor "green" "" . (\s->"")
                      , ppUrgent = xmobarColor "yellow" "orange" . wrap ">" "<" . xmobarStrip
                      , ppOrder = \(ws:_:t:_) -> [ws,t]
                      }
      } `additionalKeys` (myKeys)
      `removeKeys` nonKeys

myKeys =
      [ ((mod1Mask .|. shiftMask, xK_z), spawn "/home/rowan/machine-configuration/scripts/lock.sh")
      , ((controlMask, xK_Print), spawn "sleep 0.2; scrot -s")
      , ((0, xK_Print), spawn "scrot")
      ] ++ [
        ((mod1Mask, key), (windows $ W.greedyView ws))
        | (key,ws) <- myWorkspaces
      ] ++ [
        ((mod1Mask .|. shiftMask, key), (windows $ W.shift ws))
        | (key,ws) <- myWorkspaces
      ] ++ [
        ((mod1Mask .|. shiftMask, xK_i),
         (do
             spawnOn "2" "firefox"
             spawnOn "3" "urxvt -name mainterm --hold"
             spawnOn "5" "urxvt --hold -e 'pulsemixer'"
         ))
      ] ++
      [ ((mod1Mask, xK_f), (sendMessage $ Toggle NBFULL))
      , ((mod1Mask .|. shiftMask, xK_space), windows W.swapMaster)
      , ((mod1Mask, xK_r), (spawn "rofi -dpi 1 -show run -show-icons -opacity \"40\" -kb-accept-entry Return -kb-row-down Control+j -kb-remove-to-eol '' -kb-row-up Control+k"))
      , ((mod1Mask, xK_s), (spawn "rofi -dpi 1 -show ssh -show-icons -opacity \"40\" -kb-accept-entry Return -kb-row-down Control+j -kb-remove-to-eol '' -kb-row-up Control+k"))
      , ((0, xF86XK_AudioLowerVolume   ), spawn "amixer set Master playback 2%-")
      , ((0, xF86XK_AudioRaiseVolume   ), spawn "amixer set Master playback 2%+")
      , ((0, xF86XK_AudioMute          ), spawn "amixer set Master toggle")
      , ((0, xF86XK_MonBrightnessUp    ), spawn "brightnessctl s 1000+")
      , ((0, xF86XK_MonBrightnessDown  ), spawn "brightnessctl s 1000-")
      , ((0, xK_Print                  ), spawn "/home/rowan/machine-configuration/scripts/screenshot.sh")
      , ((mod1Mask, xK_Print           ), spawn "/home/rowan/machine-configuration/scripts/screenshot-region.sh")
      , ((mod1Mask, xK_d               ), spawn "/home/rowan/machine-configuration/scripts/setup_external_monitor.sh")
      ]

nonKeys =
      [
        (mod1Mask, xK_Return)
      ]


mWManager :: ManageHook
mWManager = composeAll . concat $
            [ [manageHook defaultConfig]
            , [manageSpawn]
            , [manageDocks]
            -- Below gets chrome_app_list to properly float
            , [(stringProperty "WM_WINDOW_ROLE") =? "bubble"  --> doFloat]
            , [(stringProperty "WM_WINDOW_ROLE") =? "pop-up"  --> doFloat]
            ]
