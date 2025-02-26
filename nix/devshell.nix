{
  pkgs,
  flake,
  system,
  perSystem,
  ...
}:
perSystem.devshell.mkShell ({
  config,
  options,
  lib,
  ...
}: let
  # TODO: Create builder function that accepts pkgs, mappings list and options
  sourceMappings = [
    {
      # TODO: magically derive via lockfile
      flakeInput = {
        inherit flake;
        name = "devshell";
      };

      # But can be done manually as well
      source = flake.inputs.devshell.outPath;
      prefix = "https://github.com/numtide/devshell/blob/${flake.inputs.devshell.rev}";
    }
    # TODO: Test "self"
    {
      source = flake.outPath;
      prefix = "";
    }
  ];

  # TODO: Clean up
  # TODO: Are there Hidden or Internal flags? eg. _module.args should be hidden
  transformDeclarations = path: let
    matches = lib.filter (mapping: lib.hasPrefix mapping.source (toString path)) sourceMappings;
  in
    if matches != []
    then let
      mapping = lib.head matches;
      relativePath = lib.removePrefix mapping.source (toString path);
    in
      mapping.prefix + relativePath
    else path;

  optionsDoc = pkgs.nixosOptionsDoc {
    inherit options;
    transformOptions = opt:
      opt
      // {
        declarations = builtins.map transformDeclarations opt.declarations;
      };
  };
  showCommand = let
    name = "show-options";
    optionsJson = "${optionsDoc.optionsJSON}/share/doc/nixos/options.json";
  in
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [pkgs.jq pkgs.fzf pkgs.mdcat];
      text = ''
        jq -r 'keys[]' ${optionsJson} | fzf "$@" --preview 'jq -r --arg key {-1} -f ${./format_options.jq} ${optionsJson} | mdcat'
      '';
    };
in {
  devshell = {
    name = ''Example Application'';
    startup.pre-commit.text = ''if [ -z "''${CI:-}" ]; then ${flake.checks.${system}.linters.shellHook} fi'';
  };

  packages =
    [
      perSystem.build-gradle-application.updateVerificationMetadata
    ]
    ++ flake.packages.${system}.default.nativeBuildInputs;

  commands = [
    {
      name = "build";
      help = "compiles, runs tests, and reports success or failure";
      command = ''gradle :clean :check :installDist'';
    }
    {
      name = "build-continuously";
      help = "automatically run build when files change";
      command = ''gradle --continuous :check :installDist'';
    }
    {
      name = "rundev";
      help = "run the software locally for manual review and testing";
      command = ''gradle :run'';
    }
    {
      name = "integration-test";
      help = "run integration tests in a production-like environment";
      command = "nix build .#checks.${system}.integrationTest";
    }
    {
      name = "lint";
      help = "run all linters - or specific ones when passed as arguments";
      command = ''pre-commit run --all-files "''${@}"'';
    }
    {
      name = "show-devshell-options";
      help = "List and describe all available devshell options";
      command = ''${lib.getExe showCommand} "''${@}"'';
    }
  ];
})
