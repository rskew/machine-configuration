{ pkgs, unstable, isGraphical, agenix, ... }:
let
  pythonEnv = pkgs.python3.withPackages (ps: with ps; [
    ipython
    pandas
    matplotlib
    seaborn
    pyyaml
    boto3
    tqdm
    duckdb
  ]);
  vim-with-custom-rc = pkgs.vim_configurable.customize {
    vimrcConfig = {
      customRC = ''
        filetype plugin indent on
        syntax on
        set number relativenumber
        set tabstop=4
        set softtabstop=4
        set expandtab
        set shiftwidth=4
        set smarttab
        set clipboard=unnamed
        set noerrorbells
        set vb t_vb=
        colorscheme torte
      '';
    };
  };
in {
  environment.systemPackages = with pkgs; [
    git
    unstable.lunarvim
    unstable.emacs
    ripgrep # for project-wide search in emacs
    fzf # for reverse history search in fish shell
    wget
    bat
    git
    tree
    zip
    unzip
    nmap
    gnupg
    sl
    htop
    file
    iotop
    jq
    pythonEnv
    kitty
    xclip
    vim-with-custom-rc
    broot
    unstable.zellij
    pgbackrest
    agenix.packages.${system}.agenix
    nix-tree
    qrencode
    rclone
    restic
    awscli2
    bashmount
    docker
    taskwarrior
    pgcli
    gh
    nettools
    pkgs.fishPlugins.fzf
  ] ++ (if isGraphical then [
    arandr
    dconf # Required for gtk3 configuration
    wmctrl
    chromium
    unstable.firefox
    vlc
    pulsemixer
    pulseaudio
    libreoffice
    simplescreenrecorder
    qgis
    unstable.slack
    unstable.zoom-us
    pkgs.gnomeExtensions.appindicator
    pkgs.gnomeExtensions.system-monitor-next
    pkgs.gnomeExtensions.paperwm
    pkgs.gnomeExtensions.switcher
    (pkgs.fishPlugins.buildFishPlugin {
      pname = "batman";
      version = "hello";
      src = pkgs.fetchFromGitHub {
        owner = "oh-my-fish";
        repo = "theme-batman";
        rev = "2a76bd81f4805debd7f137cb98828bff34570562";
        sha256 = "Ko4w9tMnIi17db174FzW44LgUdui/bUzPFEHEHv//t4=";
      };
    })
    libnotify
  ] else []);

  programs.dconf.profiles.user.databases = [
    {
      lockAll = true;
      settings = {
        "org/gnome/desktop/input-sources" = {
          xkb-options = [
            "altwin:swap_alt_win"
          ];
        };
        "org/gnome/desktop/peripherals/keyboard" = {
          delay = pkgs.lib.gvariant.mkUint32 200;
          repeat-interval = pkgs.lib.gvariant.mkUint32 28;
          repeat = true;
        };
        "org/gnome/shell" = {
          disable-user-extensions = false;
          enabled-extensions = with pkgs.gnomeExtensions; [
            appindicator.extensionUuid
            paperwm.extensionUuid
            switcher.extensionUuid
            system-monitor.extensionUuid
            workspace-indicator.extensionUuid
            system-monitor-next.extensionUuid
          ];
        };
        "org/gnome/desktop/wm/preferences" = {
          num-workspaces = pkgs.lib.gvariant.mkInt32 6;
          workspace-names = [ "1" "2" "3" "4" "5" "6" ];
          audible-bell = false;
        };
        "org/gnome/desktop/wm/keybindings" = {
          switch-to-workspace-1 = [ "<Super>1" ];
          switch-to-workspace-2 = [ "<Super>2" ];
          switch-to-workspace-3 = [ "<Super>3" ];
          switch-to-workspace-4 = [ "<Super>4" ];
          switch-to-workspace-5 = [ "<Super>5" ];
          switch-to-workspace-6 = [ "<Super>6" ];
          move-to-workspace-1 = [ "<Shift><Super>1" ];
          move-to-workspace-2 = [ "<Shift><Super>2" ];
          move-to-workspace-3 = [ "<Shift><Super>3" ];
          move-to-workspace-4 = [ "<Shift><Super>4" ];
          move-to-workspace-5 = [ "<Shift><Super>5" ];
          move-to-workspace-6 = [ "<Shift><Super>6" ];
          minimize = pkgs.lib.gvariant.mkEmptyArray (pkgs.lib.gvariant.type.string);
        };
        "org/gnome/shell/keybindings" = {
          switch-to-application-1 = pkgs.lib.gvariant.mkEmptyArray (pkgs.lib.gvariant.type.string);
          switch-to-application-2 = pkgs.lib.gvariant.mkEmptyArray (pkgs.lib.gvariant.type.string);
          switch-to-application-3 = pkgs.lib.gvariant.mkEmptyArray (pkgs.lib.gvariant.type.string);
          switch-to-application-4 = pkgs.lib.gvariant.mkEmptyArray (pkgs.lib.gvariant.type.string);
          switch-to-application-5 = pkgs.lib.gvariant.mkEmptyArray (pkgs.lib.gvariant.type.string);
          switch-to-application-6 = pkgs.lib.gvariant.mkEmptyArray (pkgs.lib.gvariant.type.string);
        };
        "org/gnome/settings-daemon/plugins/media-keys" = {
          custom-keybindings = [
            "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"
            "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/"
          ];
        };
        "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0" = {
          binding = "<Control><Super>Return";
          command = "kitty";
          name = "new-terminal";
        };
        "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1" = {
          binding = "<Control>m";
          command = "/home/rowan/machine-configuration/scripts/toggle_mic_mute.sh";
          name = "toggle-mic-mute";
        };
      };
    }
  ];
}
