// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Alex Moncks
//
// geo3d_replay: runs a geo3d stimulus file (the format of sim/tb_engine.v in
// the V9968_Cartridge repository) through Geo3DCore and writes the log in the
// same format, so it can be diffed against the *_expect.txt files of the
// Python reference model.
//
//   stimulus: W <sel> <byte hex>   port write (sel 0 = index, 1 = data)
//             R                    wait for RUN busy to clear
//             K                    read SKIPPED/DRAWN/CULLED (index 0x4A)
//             F <n>                frame marker
//   log:      L <11 bytes> / M <19 bytes> per VDP command, K ..., F n
//
// Build: g++ -std=c++23 -O2 -Isrc/video tools/geo3d_replay.cc src/video/Geo3DCore.cc

#include "Geo3DCore.hh"

#include <cstdio>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>

using openmsx::Geo3DCore;

int main(int argc, char** argv)
{
	if (argc != 3) {
		std::cerr << "usage: geo3d_replay <stim.txt> <got.txt>\n";
		return 2;
	}
	std::ifstream in(argv[1]);
	if (!in) { std::cerr << "cannot open " << argv[1] << '\n'; return 1; }
	FILE* out = std::fopen(argv[2], "w");
	if (!out) { std::cerr << "cannot write " << argv[2] << '\n'; return 1; }

	Geo3DCore g;
	unsigned nCmd = 0, frames = 0;
	std::string line;
	while (std::getline(in, line)) {
		std::istringstream is(line);
		std::string op;
		if (!(is >> op)) continue;
		if (op == "W") {
			unsigned sel, b;
			is >> sel >> std::hex >> b;
			if (sel & 1) g.writeData(uint8_t(b)); else g.writeIndex(uint8_t(b));
		} else if (op == "R") {
			// the VDP is idle at once here: issue every command, then drain
			while (g.readStatus() & 1) {
				if (g.hasCommand()) {
					const auto& c = g.nextCommand();
					std::fputs(c.isLrmm() ? "M" : "L", out);
					for (unsigned k = 0; k < c.size; ++k) std::fprintf(out, " %02x", c.bytes[k]);
					std::fputc('\n', out);
					++nCmd;
				} else {
					g.finishRun();
				}
			}
		} else if (op == "K") {
			g.writeIndex(0x4A);
			uint8_t k[6];
			for (auto& x : k) x = g.readData();
			std::fprintf(out, "K %02x%02x %02x%02x %02x%02x\n", k[1], k[0], k[3], k[2], k[5], k[4]);
		} else if (op == "F") {
			unsigned n;
			is >> n;
			std::fprintf(out, "F %u\n", n);
			++frames;
		}
	}
	std::fclose(out);
	std::printf("frames: %u, VDP commands: %u\n", frames, nCmd);
	return 0;
}
