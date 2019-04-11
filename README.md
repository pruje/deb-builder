# ssh-notify debian package builder

Build a debian package from sources.

## Build instructions
1. Create and edit your build config in `conf` (see `examples`)
2. Clone your sources in `src` directory: `git clone ... src`
3. Be sure that your submodules are initialized and up to date
4. Run `./build.sh` script (you need to have sudo access)
5. Package and checksum are available in the `archives/{version}` directory

## License
This project is licensed under the MIT License. See [LICENSE.md](LICENSE.md) for the full license text.

## Credits
Author: Jean Prunneaux https://jean.prunneaux.com

Website: https://github.com/pruje/deb-builder
