# Digital Companion — Pixel Workshop

Figma: https://www.figma.com/design/syQM2pShfeCTfXms0HmzTB
Folder: Big Leap → Misc → John’s Projects.

Editable portrait layouts, 430 × 932:
- Care: node 2:51
- Stats: node 2:52
- Battle: node 2:53

The Care / Stats / Battle navigation tabs link between the three frames. Other actions illustrate the proposed interface and do not run game logic.

Direction: original forest and cream palette, Pixelify Sans display text, original Geist body text, Geist Mono numbers, pixel icons, segmented meters, hard edges and offset shadows.

The file includes shared icon, button, header and navigation components; 2 variable collections containing 36 variables; 6 text styles; a hard-shadow effect; and a Digimon Up source-reference strip.

Downloaded source assets: Documents/Digimon/Digimon Up Assets/Sprite. UI_Partner_Agumon.png is used on the screens. Reference strip includes Common_Btn_Default_On.png, Common_Training_Popup_Bg.png, Common_Progress_01.png, Common_Icon_Defensive.png, and Farm_Icon_MeatBascket.png.

Forest artwork comes from digital-companion-prototype/assets-source/forest-arena/forest-v1/sources/c67502d762649ec770338422e6aaf31594ef4362db2b65f39c6285478e3d833e.png.

Gameplay data is illustrative. Hunger 18% and fed 82% represent the same state. Battle uses the existing coaching commands Auto, Attack, Defend, Keep Distance. Implementation should confirm leaving an active fight before abandoning the reward.

QA: visually inspected all three full-resolution screens and major sections; verified 430 × 932 geometry, expected font families, six cross-screen navigation reactions, and no overflowing auto-layout children. Source web-app capture instrumentation was removed; app/layout.tsx has no remaining diff from this work.
