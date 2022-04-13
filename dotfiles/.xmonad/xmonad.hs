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

myExtraWorkspaces = [(xK_0, "0"),(xK_minus, "-"),(xK_equal, "=")]

myWorkspaces = ["1","2","3","4","5","6","7","8","9"] ++ (map snd myExtraWorkspaces)

main = do
  xmproc <- spawnPipe "xmobar /home/rowan/.xmobarrc"
  xmonad $ withUrgencyHook NoUrgencyHook $ docks defaultConfig
      { modMask            = mod1Mask
      , borderWidth        = 1
      , terminal           = "urxvt -cd \"$PWD\""
      , normalBorderColor  = "#000"
      , focusedBorderColor = "#0af"
      , workspaces = myWorkspaces
      --, manageHook = manageSpawn <+> manageDocks <+> manageHook defaultConfig
      , manageHook = mWManager
      , layoutHook = mkToggle (single NBFULL) $ avoidStruts
                                              $ spacingRaw False (Border 0 6 6 6) True (Border 6 6 6 6) True
                                              $ layoutHook defaultConfig
      , handleEventHook = fullscreenEventHook
      , startupHook = setWMName "LG3D"
      , logHook = dynamicLogWithPP xmobarPP
                      { ppOutput = hPutStrLn xmproc
                      --, ppTitle = xmobarColor "green" "" . shorten 0 --50
                      , ppTitle = xmobarColor "green" "" . (\s->"")
                      , ppUrgent = xmobarColor "yellow" "red" . wrap ">" "<" . xmobarStrip
                      }
      } `additionalKeys` (myKeys)
      `removeKeys` nonKeys

myKeys =
      [ ((mod1Mask .|. shiftMask, xK_z), spawn "/home/rowan/scripts/lock.sh")
      , ((controlMask, xK_Print), spawn "sleep 0.2; scrot -s")
      , ((0, xK_Print), spawn "scrot")
      ] ++ [
        ((mod1Mask, key), (windows $ W.greedyView ws))
        | (key,ws) <- myExtraWorkspaces
      ] ++ [
        ((mod1Mask .|. shiftMask, key), (windows $ W.shift ws))
        | (key,ws) <- myExtraWorkspaces
      ] ++ [
        ((mod1Mask .|. shiftMask, xK_i),
         (do
             spawnOn "2" "firefox"
             spawnOn "3" "urxvt -name mainterm --hold"
             spawnOn "5" "urxvt --hold -e 'pulsemixer'"
         ))
      ] ++ [
        ((mod1Mask, xK_f), (sendMessage $ Toggle NBFULL))
      ] ++ [
        ((mod1Mask .|. shiftMask, xK_space), windows W.swapMaster)
      ] ++ [
        ((mod1Mask, xK_r), (spawn "rofi -dpi 1 -show run -show-icons -opacity \"40\""))
      ] ++ [
        ((mod1Mask, xK_d), (spawn "rofi -dpi 1 -show drun -show-icons -opacity \"40\""))
      ] ++ [
        ((mod1Mask, xK_s), (spawn "rofi -dpi 1 -show ssh"))
      ]

nonKeys =
      [
        (mod1Mask, xK_Return)
      ]


mWManager :: ManageHook
mWManager = composeAll . concat $
            [ [manageHook defaultConfig]
            , [manageDocks]
            -- windows that should be sent to a workspace
            , [className =? "Firefox"     --> doShift "2"]
            , [resource =? "mainterm"     --> doShift "3"]
            , [resource =? "pulsemixer"   --> doShift "5"]
            -- Below gets chrome_app_list to properly float
            , [(stringProperty "WM_WINDOW_ROLE") =? "bubble"  --> doFloat]
            , [(stringProperty "WM_WINDOW_ROLE") =? "pop-up"  --> doFloat]
            ]
