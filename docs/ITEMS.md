# Item List

Every item in Bloxov. **Generated** from `scripts/item_db.gd` by `tools/gen_item_list.py`;
edit the item database, then re-run the script (don't edit this file by hand).

## Items

| Item | Type | Rarity | Size | Stack | Value (each) | Notes | Description |
|---|---|---|---|---|---|---|---|
| Stinger (`pistol`) | Weapon | Common | 2×1 | 1 | $3,000 | secondary slot; semi-auto; 14 dmg, 360 rpm, 12-round mag, pistol ammo; damage drops to 60% from 15 to 40 m; attachment slots: barrel, sight | Small sidearm. Quick to aim, one shot per click. |
| Viper (`viper`) | Weapon | Uncommon | 2×1 | 1 | $6,500 | secondary slot; semi-auto; 24 dmg, 170 rpm, 7-round mag, pistol ammo; damage drops to 60% from 15 to 40 m; attachment slots: barrel, sight | Heavy sidearm. Hits almost twice as hard as the Stinger, holds 7 and kicks. |
| Wasp (`smg`) | Weapon | Uncommon | 3×2 | 1 | $10,000 | primary slot; full-auto; 20 dmg, 750 rpm, 25-round mag, smg ammo; damage drops to 55% from 15 to 40 m; attachment slots: scope, barrel, grip, mag | Small and fast. Sprays at close range, weak far away. |
| Mauler (`shotgun`) | Weapon | Uncommon | 4×1 | 1 | $11,000 | primary slot; semi-auto; 8 pellets x 14 dmg, 70 rpm, 6-round mag, shells; damage drops to 40% from 12 to 30 m; attachment slots: barrel, grip, sight | Pump shotgun. Deadly up close, useless far away. Loads one shell at a time. |
| Hound (`ak`) | Weapon | Uncommon | 4×2 | 1 | $12,500 | primary slot; full-auto; 28 dmg, 600 rpm, 30-round mag, rifle ammo; damage drops to 65% from 30 to 80 m; attachment slots: scope, barrel, grip, mag | Old army rifle, full auto. Hits hard, kicks harder. |
| Hornet (`hornet`) | Weapon | Uncommon | 3×2 | 1 | $14,000 | primary slot; full-auto; 24 dmg, 700 rpm, 30-round mag, smg ammo; damage drops to 60% from 20 to 50 m; attachment slots: scope, barrel, grip, mag | Heavier SMG. Fires slower than the Wasp but hits harder and holds up farther out. |
| Brawler (`brawler`) | Weapon | Uncommon | 4×1 | 1 | $15,000 | primary slot; semi-auto; 8 pellets x 12 dmg, 120 rpm, 8-round mag, shells; damage drops to 40% from 12 to 30 m; attachment slots: barrel, grip, sight | Semi-auto shotgun. No pump: it fires as fast as you click. Wider spread than the Mauler. |
| Lancer (`sniper`) | Weapon | Rare | 5×1 | 1 | $22,500 | primary slot; semi-auto; 90 dmg, 40 rpm, 5-round mag, sniper ammo; damage drops to 85% from 80 to 200 m; attachment slots: scope, barrel, grip, mag | Bolt-action sniper rifle. Two body shots or one to the head. Terrible from the hip. |
| Talon (`talon`) | Weapon | Rare | 5×1 | 1 | $26,000 | primary slot; semi-auto; 45 dmg, 120 rpm, 10-round mag, sniper ammo; damage drops to 80% from 60 to 150 m; attachment slots: scope, barrel, grip, mag | Semi-auto marksman rifle. Weaker shots than the Lancer (three to the body, no one-shot heads), but ten of them. |
| Reaper (`reaper`) | Weapon | Epic | 4×2 | 1 | $30,000 | primary slot; full-auto; 30 dmg, 650 rpm, 30-round mag, rifle ammo; damage drops to 65% from 30 to 80 m; attachment slots: scope, barrel, grip, mag | Site Zero's own rifle. Takes Hound rounds, shoots straighter and faster. Only Raijin carries one. |
| Taped Grip (`taped_grip`) | Attachment | Common | 1×1 | 1 | $400 | fits Hound, Reaper, Wasp, Mauler, Lancer, Hornet, Brawler, Talon; recoil x0.9, recoil_yaw x0.9 | A block of wood taped under the barrel. A little less kick. |
| Fast Mag (`fast_mag`) | Attachment | Common | 1×1 | 1 | $500 | fits Hound, Reaper, Wasp, Lancer, Hornet, Talon; reload x0.85 | A mag with a pull tab. Same size, 15% quicker to reload. |
| Muzzle Brake (`muzzle_brake`) | Attachment | Common | 1×1 | 1 | $600 | fits Hound, Reaper, Stinger, Wasp, Lancer, Viper, Hornet, Talon; recoil x0.92, recoil_yaw x0.92, noise x1.15 | Vents the blast sideways. Less kick, but your shots are louder. |
| Red Dot (`red_dot`) | Attachment | Uncommon | 1×1 | 1 | $500 | fits Hound, Reaper, Stinger, Wasp, Mauler, Lancer, Viper, Hornet, Brawler, Talon; ads_time x0.9, ads_fov x0.92 | Small sight with a red dot. Quicker to aim, a little more zoom. |
| Choke (`choke`) | Attachment | Uncommon | 1×1 | 1 | $700 | fits Mauler, Brawler; pellet_spread x0.85 | Shotgun muzzle. Keeps the pellets tighter. |
| Foregrip (`foregrip`) | Attachment | Uncommon | 1×1 | 1 | $800 | fits Hound, Reaper, Wasp, Mauler, Lancer, Hornet, Brawler, Talon; recoil x0.82, recoil_yaw x0.82 | Something to hold on to. Less kick. |
| Holo Sight (`holo_sight`) | Attachment | Uncommon | 1×1 | 1 | $1,200 | fits Hound, Reaper, Stinger, Wasp, Mauler, Lancer, Viper, Hornet, Brawler, Talon; ads_time x0.85, ads_fov x0.92, spread x0.95 | A better sight. Quicker to aim than a red dot, and steadier aimed. |
| Extended Mag (`ext_mag`) | Attachment | Rare | 1×1 | 1 | $1,200 | fits Hound, Reaper, Wasp, Lancer, Hornet, Talon; mag x1.5, reload x1.1 | Holds more rounds. Slower to reload. |
| 4x Scope (`scope_4x`) | Attachment | Rare | 2×1 | 1 | $1,500 | fits Hound, Reaper, Wasp, Lancer, Hornet, Talon; ads_time x1.2, ads_fov = 30.0 | Brings far targets close. Slower to aim. |
| Suppressor (`suppressor`) | Attachment | Rare | 2×1 | 1 | $1,800 | fits Hound, Reaper, Stinger, Wasp, Lancer, Viper, Hornet, Talon; noise x0.5, recoil x0.95, recoil_yaw x0.95 | Your shots are heard half as far. A little less kick. |
| Full Choke (`full_choke`) | Attachment | Epic | 1×1 | 1 | $2,000 | fits Mauler, Brawler; pellet_spread x0.75 | The tightest shotgun muzzle. Pellets stay together much farther. |
| Tactical Grip (`tactical_grip`) | Attachment | Epic | 1×1 | 1 | $2,500 | fits Hound, Reaper, Wasp, Mauler, Lancer, Hornet, Brawler, Talon; recoil x0.75, recoil_yaw x0.75, ads_time x0.95 | The best grip there is. Much less kick, a little quicker to aim. |
| 8x Scope (`scope_8x`) | Attachment | Epic | 2×1 | 1 | $3,000 | fits Lancer; ads_time x1.3, ads_fov = 14.0 | A sniper's scope. Huge zoom, slow to aim. |
| Drum Mag (`drum_mag`) | Attachment | Epic | 2×2 | 1 | $3,000 | fits Hound, Reaper, Wasp, Lancer, Hornet, Talon; mag x2.0, reload x1.25, ads_time x1.1 | Twice the rounds. Heavy: slower to reload and to aim. |
| Heavy Suppressor (`heavy_suppressor`) | Attachment | Epic | 2×1 | 1 | $4,000 | fits Hound, Reaper, Stinger, Wasp, Lancer, Viper, Hornet, Talon; noise x0.4, recoil x0.88, recoil_yaw x0.88, ads_time x1.05 | Long, fat and quiet. Heard less than half as far, less kick, a little slower to aim. |
| Light Armor (`armor_light`) | Armor | Uncommon | 3×3 | 1 | $7,500 | -20% damage taken | Soft vest. Takes the edge off a hit. |
| Heavy Armor (`armor_heavy`) | Armor | Rare | 3×3 | 1 | $20,000 | -40% damage taken | Plated vest. Stops a lot. |
| Assault Armor (`armor_assault`) | Armor | Epic | 3×3 | 1 | $35,000 | -50% damage taken; only from one-off finds:  | Site Zero plate carrier. The best armor there is. Only off Raijin. |
| Old Helmet (`helmet_basic`) | Helmet | Uncommon | 2×2 | 1 | $5,000 | -25% head damage taken | Dented steel pot. Better than nothing on your head. |
| Combat Helmet (`helmet_good`) | Helmet | Rare | 2×2 | 1 | $15,000 | -45% head damage taken | Army helmet. Takes a hit to the head well. |
| Assault Helmet (`helmet_assault`) | Helmet | Epic | 2×2 | 1 | $25,000 | -55% head damage taken; only from one-off finds:  | Site Zero helmet with a face plate. Only off Raijin. |
| Small Backpack (`backpack_small`) | Backpack | Common | 3×3 | 1 | $2,000 | 4×3 storage | A school bag. Better than pockets. |
| Medium Backpack (`backpack_medium`) | Backpack | Uncommon | 3×3 | 1 | $4,500 | 5×4 storage | Hiking pack with room for a good haul. |
| Large Backpack (`backpack_large`) | Backpack | Rare | 4×4 | 1 | $10,000 | 6×5 storage | Big army rucksack. Carry everything home. |
| Raid Pack (`backpack_raid`) | Backpack | Epic | 4×4 | 1 | $18,000 | 7×6 storage; only from one-off finds:  | Raijin's own pack. Nothing carries more. |
| Pistol Rounds (`pistol_ammo`) | Ammo | Common | 1×1 | 50 | $10 | full stack $500 | Pistol rounds for the Stinger and the Viper. Loaded when you reload. |
| SMG Rounds (`smg_ammo`) | Ammo | Common | 1×1 | 90 | $10 | full stack $900 | Small rounds for the Wasp and the Hornet. Loaded when you reload. |
| Rifle Rounds (`rifle_ammo`) | Ammo | Common | 1×1 | 120 | $15 | full stack $1,800 | Rifle rounds for the Hound and the Reaper. Loaded when you reload. |
| Shotgun Shells (`shells`) | Ammo | Common | 1×1 | 30 | $30 | full stack $900 | Buckshot for the Mauler and the Brawler. Loaded one at a time. |
| Sniper Rounds (`sniper_ammo`) | Ammo | Uncommon | 1×1 | 30 | $75 | full stack $2,250 | Long rounds for the Lancer and the Talon. Loaded when you reload. |
| Bandage (`bandage`) | Healing | Common | 1×1 | 5 | $500 | heals 25 over 2 s | Stops the bleeding. Quick to use. |
| Painkillers (`painkillers`) | Healing | Uncommon | 1×1 | 6 | $900 | heals 15 over 1 s | A few pills. Takes the edge off, fast. |
| Medkit (`medkit`) | Healing | Uncommon | 2×1 | 3 | $2,000 | heals 70 over 4 s | Field kit. Heals a lot, takes a while. |
| Trauma Kit (`trauma_kit`) | Healing | Rare | 2×2 | 1 | $5,500 | heals 100 over 7 s | Everything a field medic carries. Patches you right up, but it takes time. |
| Energy Drink (`energy_drink`) | Drink | Common | 1×1 | 1 | $1,200 |  | Fills your stamina, then sprinting costs none for 10 s. |
| Frag Grenade (`grenade`) | Throwable | Uncommon | 1×1 | 3 | $3,000 |  | Pull, throw, take cover. Goes off 3 seconds after it leaves your hand. |
| Bank Vault Key (`bank_vault_key`) | Key | Rare | 1×1 | 1 | $3,500 | opens BankVaultDoor | Opens the vault in the bank. |
| Impound Key (`impound_key`) | Key | Rare | 1×1 | 1 | $3,500 | opens ImpoundDoor | Opens the impound room in Harbor Tower, off the harbourmaster's office. |
| Bunker Key (`bunker_key`) | Key | Epic | 1×1 | 1 | $6,000 | opens BunkerDoor | Opens the bunker under the town hall. Bon keeps one on him. |
| Bolts (`bolts`) | Valuable | Common | 1×1 | 10 | $120 |  | A handful of nuts and bolts. Small, but always needed. |
| Canned Beans (`beans`) | Valuable | Common | 1×1 | 1 | $150 |  | Somebody's lunch. Traders pay for food out here. |
| Wires (`wires`) | Valuable | Common | 1×1 | 1 | $180 |  | Copper wire stripped from a wall. Useful for fixing things. |
| Water Bottle (`water`) | Valuable | Common | 1×1 | 1 | $200 |  | Clean water is rare out here. Traders pay for it. |
| Scrap Metal (`scrap`) | Valuable | Common | 2×1 | 3 | $250 |  | Bent metal. Worth a little to the right buyer. |
| Duct Tape (`duct_tape`) | Valuable | Common | 1×1 | 1 | $300 |  | Fixes everything. Sells well. |
| Ration Pack (`ration`) | Valuable | Uncommon | 1×1 | 1 | $700 |  | Novarran army meal. Tastes like cardboard, sells like gold. |
| Old Phone (`phone`) | Valuable | Uncommon | 1×1 | 1 | $800 |  | Cracked screen, still works. Someone wants the parts. |
| Med Parts (`med_supplies`) | Valuable | Uncommon | 1×1 | 1 | $800 |  | Crafting part: gauze, syringes, pills. Make bandages and medkits at the workbench, or sell them to clinics. |
| Raider Dog Tag (`dog_tag`) | Valuable | Uncommon | 1×1 | 1 | $900 | only from one-off finds:  | Taken off a Raider. Proof of a kill, and traders pay for it. |
| Fuel Can (`fuel_can`) | Valuable | Uncommon | 2×2 | 1 | $900 |  | Half full. Every generator in Bloxov wants it. |
| Powder Tin (`gunpowder`) | Valuable | Uncommon | 1×1 | 1 | $1,000 |  | A tin of gunpowder. Keep it away from fire. |
| Car Battery (`battery`) | Valuable | Uncommon | 2×2 | 1 | $1,200 |  | Heavy and worth it. |
| Novarra Badge (`novarra_badge`) | Valuable | Rare | 1×1 | 1 | $2,000 |  | A Novarran soldier's unit badge. Collectors and traders want them. |
| Gold Watch (`gold_watch`) | Valuable | Rare | 1×1 | 1 | $2,500 |  | Somebody's pride. Now yours. |
| PMC Dog Tag (`player_tag`) | Valuable | Rare | 1×1 | 1 | $2,500 | only from one-off finds:  | Taken off a PMC you killed online. Traders pay well for these. |
| Cash Bundle (`cash`) | Valuable | Rare | 1×1 | 1 | $3,000 |  | Old Novarran notes. Still good with the traders. |
| Novarra Field Report (`intel_novarra`) | Valuable | Rare | 1×1 | 1 | $3,000 |  | Novarran army papers: patrols, supply runs, names. Someone will pay to read them. |
| Hard Drive (`hard_drive`) | Valuable | Rare | 1×1 | 1 | $3,500 |  | Pulled from an office computer. Nobody wiped it. |
| Laptop (`laptop`) | Valuable | Rare | 2×1 | 1 | $4,000 |  | Novarran office laptop. The data is worth more than the machine. |
| Processor (`cpu`) | Valuable | Rare | 1×1 | 1 | $5,000 |  | A computer processor. Small, light and worth a lot. |
| Exion Medal (`exion_medal`) | Valuable | Epic | 1×1 | 1 | $7,000 |  | Brotherhood medal with the X1 mark. Only their best get one. |
| Military Chip (`mil_chip`) | Valuable | Epic | 1×1 | 1 | $7,500 |  | Exion military hardware. Very wanted. |
| Gold Bar (`gold_bar`) | Valuable | Epic | 1×1 | 1 | $8,000 |  | Straight from the vault. |
| Exion Orders (`intel_exion`) | Valuable | Epic | 1×1 | 1 | $8,500 |  | Sealed orders with the Brotherhood's X1 mark. Dangerous to carry, worth a fortune. |
| Bon's Dog Tag (`bon_tag`) | Valuable | Epic | 1×1 | 1 | $9,000 | only from one-off finds:  | Bon's own tag. Everyone in Bloxov will want to see this. |
| Antique Vase (`vase`) | Valuable | Epic | 2×2 | 1 | $9,000 |  | Old and fragile. Don't drop it. |
| Graphics Card (`gpu`) | Valuable | Epic | 2×1 | 1 | $10,000 |  | A high-end graphics card. Worth more than most guns. |
| Subject 09 File: Intake (`nine_file_1`) | Valuable | Legendary | 1×1 | 1 | $0 | only from one-off finds: 100% in LabWing_Safe6 | Site Zero intake record, page one of three. Subject 09: Brotherhood conscript, volunteered for the program, memory wiped on arrival. 'Strong, quiet, asks nothing.' Bring all three files out to unlock NINE. |
| Subject 09 File: Trials (`nine_file_2`) | Valuable | Legendary | 1×1 | 1 | $0 | only from one-off finds: 100% in LabWing_Crate7 | Trial log, page two of three. Subject 09 ran the ring for six hours without stopping and lifted the gate the guards couldn't. In the margin: 'It has started asking questions.' Bring all three files out to unlock NINE. |
| Subject 09 File: Escape (`nine_file_3`) | Valuable | Legendary | 1×1 | 1 | $0 | only from one-off finds: 100% in LabWing_Crate9 | Server log, page three of three. The night of the strike the power failed, cell 09 opened, and the cameras show the subject walking out through the sub bay. Last line: 'Do not pursue. It knows the way.' Bring all three files out to unlock NINE. |
| Diamond Ring (`diamond_ring`) | Valuable | Legendary | 1×1 | 1 | $15,000 |  | A real diamond. Someone kept it in the vault for a reason. |
| Rare Crystal (`crystal`) | Valuable | Legendary | 1×1 | 1 | $18,000 |  | Nobody knows where these come from. Everyone wants one. |
| Golden Toilet (`golden_toilet`) | Valuable | Legendary | 2×3 | 1 | $50,000 | only from one-off finds: 3% in Bank_Safe1, 3% in Bank_Safe2 | Yes, really. |
| Holy Grail (`holy_grail`) | Valuable | Legendary | 2×2 | 1 | $75,000 | only from one-off finds: 3% in Bank_Safe1, 3% in Bank_Safe2, 1% in Bunker_Safe1, 1% in Bunker_Safe2, 1% in Bunker_Safe3, 1% in Bunker_Safe4 | The most valuable thing in Bloxov. Only ever seen in the town hall and the bank vault. |
| The Formula (`formula`) | Valuable | Legendary | 1×2 | 1 | $100,000 | only from one-off finds:  | What Site Zero was built to make. Raijin never lets it out of his sight. |

Nothing wears out for now: durability (armor, helmets, keys, guns) is its own update later (owner).

## Where items come from

Each container rolls a number of times; each roll picks from its table by weight.
A rarity entry (e.g. *rare*) means a random **valuable** of that rarity.
A roll gives one item, except these come as a stack: Rifle Rounds 20–60, SMG Rounds 15–40, Shotgun Shells 5–12, Sniper Rounds 3–10, Bandage 1–2.

### Crate (1–3 rolls)

| Entry | Chance per roll |
|---|---|
| Rifle Rounds | 25% |
| Common valuable (Canned Beans, Water Bottle, Duct Tape, Scrap Metal, Bolts, Wires) | 25% |
| Bandage | 15% |
| Uncommon valuable (Ration Pack, Old Phone, Car Battery, Powder Tin, Fuel Can, Med Parts) | 10% |
| Pistol Rounds | 7% |
| Energy Drink | 4% |
| Medkit | 3% |
| SMG Rounds | 3% |
| Shotgun Shells | 3% |
| Rare valuable (Gold Watch, Laptop, Cash Bundle, Novarra Field Report, Processor, Novarra Badge, Hard Drive) | 3% |
| Small Backpack | 2% |
| Sniper Rounds | 1% |

### Locker (2–4 rolls)

| Entry | Chance per roll |
|---|---|
| Uncommon valuable (Ration Pack, Old Phone, Car Battery, Powder Tin, Fuel Can, Med Parts) | 17% |
| Common valuable (Canned Beans, Water Bottle, Duct Tape, Scrap Metal, Bolts, Wires) | 12% |
| Rifle Rounds | 10% |
| Rare valuable (Gold Watch, Laptop, Cash Bundle, Novarra Field Report, Processor, Novarra Badge, Hard Drive) | 10% |
| Medkit | 8% |
| Bandage | 7% |
| Pistol Rounds | 4% |
| SMG Rounds | 3% |
| Shotgun Shells | 3% |
| Stinger | 3% |
| Energy Drink | 3% |
| Light Armor | 3% |
| Old Helmet | 3% |
| Epic valuable (Gold Bar, Exion Orders, Military Chip, Exion Medal, Graphics Card, Antique Vase) | 3% |
| Frag Grenade | 2% |
| Small Backpack | 2% |
| Wasp | 1% |
| Mauler | 1% |
| Sniper Rounds | 1% |
| Powder Tin | 1% |
| Medium Backpack | 1% |
| Novarra Field Report | 1% |

### Field ()

| Entry | Chance per roll |
|---|---|
| Rifle Rounds | 28% |
| Bandage | 19% |
| Pistol Rounds | 11% |
| Canned Beans | 7% |
| Water Bottle | 7% |
| SMG Rounds | 6% |
| Shotgun Shells | 6% |
| Energy Drink | 6% |
| Scrap Metal | 6% |
| Bolts | 5% |

### Safe (2–3 rolls, loud to open)

| Entry | Chance per roll |
|---|---|
| Rare valuable (Gold Watch, Laptop, Cash Bundle, Novarra Field Report, Processor, Novarra Badge, Hard Drive) | 38% |
| Epic valuable (Gold Bar, Exion Orders, Military Chip, Exion Medal, Graphics Card, Antique Vase) | 30% |
| Legendary valuable (Diamond Ring, Rare Crystal) | 15% |
| Uncommon valuable (Ration Pack, Old Phone, Car Battery, Powder Tin, Fuel Can, Med Parts) | 11% |
| Heavy Armor | 3% |
| Combat Helmet | 3% |

### Scav (body bag, 1–3 rolls)

| Entry | Chance per roll |
|---|---|
| Rifle Rounds | 29% |
| Bandage | 15% |
| Common valuable (Canned Beans, Water Bottle, Duct Tape, Scrap Metal, Bolts, Wires) | 15% |
| SMG Rounds | 7% |
| Pistol Rounds | 7% |
| Uncommon valuable (Ration Pack, Old Phone, Car Battery, Powder Tin, Fuel Can, Med Parts) | 7% |
| Shotgun Shells | 6% |
| Medkit | 4% |
| Energy Drink | 3% |
| Stinger | 3% |
| Rare valuable (Gold Watch, Laptop, Cash Bundle, Novarra Field Report, Processor, Novarra Badge, Hard Drive) | 3% |

### Pmc ()

| Entry | Chance per roll |
|---|---|
| Rifle Rounds | 19% |
| Uncommon valuable (Ration Pack, Old Phone, Car Battery, Powder Tin, Fuel Can, Med Parts) | 13% |
| Bandage | 8% |
| Medkit | 8% |
| Common valuable (Canned Beans, Water Bottle, Duct Tape, Scrap Metal, Bolts, Wires) | 8% |
| SMG Rounds | 6% |
| Rare valuable (Gold Watch, Laptop, Cash Bundle, Novarra Field Report, Processor, Novarra Badge, Hard Drive) | 6% |
| Shotgun Shells | 5% |
| Frag Grenade | 4% |
| Pistol Rounds | 4% |
| Stinger | 3% |
| Energy Drink | 3% |
| Sniper Rounds | 2% |
| Red Dot | 2% |
| Foregrip | 2% |
| Taped Grip | 1% |
| Muzzle Brake | 1% |
| Fast Mag | 1% |
| Epic valuable (Gold Bar, Exion Orders, Military Chip, Exion Medal, Graphics Card, Antique Vase) | 1% |
| 4x Scope | 1% |
| Suppressor | 1% |
| Extended Mag | 1% |
| Holo Sight | 1% |
| Tactical Grip | 1% |
| Heavy Suppressor | 1% |
| Drum Mag | 1% |

### Raider (body bag, 2–4 rolls)

| Entry | Chance per roll |
|---|---|
| Rifle Rounds | 19% |
| Uncommon valuable (Ration Pack, Old Phone, Car Battery, Powder Tin, Fuel Can, Med Parts) | 12% |
| Bandage | 7% |
| Medkit | 7% |
| Common valuable (Canned Beans, Water Bottle, Duct Tape, Scrap Metal, Bolts, Wires) | 7% |
| SMG Rounds | 6% |
| Rare valuable (Gold Watch, Laptop, Cash Bundle, Novarra Field Report, Processor, Novarra Badge, Hard Drive) | 6% |
| Shotgun Shells | 5% |
| Frag Grenade | 4% |
| Pistol Rounds | 4% |
| Stinger | 3% |
| Energy Drink | 2% |
| Sniper Rounds | 2% |
| Red Dot | 2% |
| Foregrip | 2% |
| Medium Backpack | 2% |
| Taped Grip | 1% |
| Muzzle Brake | 1% |
| Fast Mag | 1% |
| Epic valuable (Gold Bar, Exion Orders, Military Chip, Exion Medal, Graphics Card, Antique Vase) | 1% |
| 4x Scope | 1% |
| Suppressor | 1% |
| Extended Mag | 1% |
| Holo Sight | 1% |
| Tactical Grip | 1% |
| Heavy Suppressor | 1% |
| Drum Mag | 1% |

## Loot by place

Containers in these places roll from their own table (crate, locker, safe) with these weights added,
so a gun store's lockers are mostly guns. Places not listed roll the plain tables.

| Place | Extra weights |
|---|---|
| Waterfall | Gold Bar 8, Diamond Ring 5, Rare Crystal 3, epic valuable 10, legendary valuable 10 |
| Bunker | Lancer 6, Sniper Rounds 10, 4x Scope 6, 8x Scope 3, Suppressor 5, Extended Mag 5, Tactical Grip 3, Heavy Suppressor 3, Drum Mag 3, Full Choke 2, Powder Tin 8, Exion Medal 6, Graphics Card 3, Med Parts 6, Exion Orders 12, Frag Grenade 8, legendary valuable 25, epic valuable 35, Military Chip 10, Heavy Armor 10, Combat Helmet 8, Hound 8, Rifle Rounds 15 |
| TownHall | Novarra Badge 6, Hard Drive 6, Novarra Field Report 8, Exion Orders 2, uncommon valuable 10 |
| Bank | Diamond Ring 5, Cash Bundle 30, Gold Bar 12, Gold Watch 15, rare valuable 10 |
| Offices | Wires 10, Processor 5, Hard Drive 8, Graphics Card 3, Novarra Field Report 5 |
| BigHouse1 | Diamond Ring 3, Gold Watch 20, Cash Bundle 15, Rare Crystal 3 |
| BigHouse2 | Processor 8, Wires 8, Graphics Card 6, Hard Drive 10, Laptop 15, Old Phone 25, Car Battery 10 |
| BigHouse3 | Antique Vase 15, epic valuable 8 |
| Police | Mauler 10, Shotgun Shells 15, Red Dot 6, Foregrip 5, Extended Mag 3, Powder Tin 4, Novarra Badge 8, Frag Grenade 8, Novarra Field Report 4, Light Armor 15, Heavy Armor 4, Old Helmet 10, Combat Helmet 3, Stinger 15, Pistol Rounds 20 |
| GunStore | Wasp 10, Mauler 10, Lancer 4, SMG Rounds 20, Shotgun Shells 20, Sniper Rounds 10, Red Dot 10, 4x Scope 6, 8x Scope 2, Suppressor 5, Choke 6, Foregrip 8, Extended Mag 6, Taped Grip 8, Muzzle Brake 6, Fast Mag 6, Holo Sight 4, Powder Tin 15, Hound 12, Stinger 15, Rifle Rounds 30, Pistol Rounds 25 |
| Pharmacy | Med Parts 25, Bandage 45, Medkit 25 |
| Grocery | Energy Drink 15, Canned Beans 30, Water Bottle 30, Ration Pack 10 |
| Diner | Energy Drink 15, Canned Beans 30, Water Bottle 30, Ration Pack 10 |
| Checkpoint | Novarra Badge 8, Frag Grenade 10, Novarra Field Report 6, Exion Orders 2 |
| GasStation | Fuel Can 25 |
| GasStationTown | Fuel Can 25 |
| Garage | Bolts 15, Wires 8, Fuel Can 20 |
| Depot | Fuel Can 10 |
| Barn | Fuel Can 8, Bolts 10 |
| Shed | Bolts 15, Wires 10 |
| Railyard | Bolts 15 |
| Junkyard | Bolts 20, Wires 15, Fuel Can 6 |
| School | Med Parts 5, Small Backpack 15, Medium Backpack 10, Large Backpack 3, Light Armor 5, Old Helmet 5 |
| ShipBridge | Gold Watch 15, Cash Bundle 15, Exion Orders 10, Diamond Ring 3, rare valuable 8, Impound Key 2 |
| ShipArmory | Hound 12, Rifle Rounds 25, Wasp 8, Mauler 8, Shotgun Shells 15, SMG Rounds 15, Light Armor 10, Heavy Armor 5, Old Helmet 8, Combat Helmet 4, Frag Grenade 10, Foregrip 5, Red Dot 5, Viper 1, Hornet 1, Brawler 1 |
| SickBay | Med Parts 25, Bandage 45, Medkit 25, Painkillers 25, Trauma Kit 6 |
| Clinic | Med Parts 20, Bandage 40, Medkit 25, Painkillers 30, Trauma Kit 6 |
| Impound | Hound 10, Wasp 8, Mauler 8, Lancer 3, Rifle Rounds 20, SMG Rounds 10, Shotgun Shells 10, Suppressor 3, Extended Mag 4, Cash Bundle 15, Gold Watch 8, rare valuable 10, epic valuable 6, Viper 1, Hornet 1, Brawler 1 |
| Galley | Energy Drink 15, Canned Beans 30, Water Bottle 30, Ration Pack 10 |
| EngineRoom | Bolts 15, Wires 10, Fuel Can 12 |
| Workshop | Bolts 15, Wires 10, Powder Tin 6, Impound Key 1 |
| LabWing | Med Parts 15, Medkit 10, Exion Orders 12, Military Chip 8, Hard Drive 8, Graphics Card 4, Processor 6, epic valuable 10 |
| LabCore | Exion Orders 12, Military Chip 10, Exion Medal 6, Graphics Card 4, legendary valuable 25, epic valuable 35, Heavy Armor 8, Combat Helmet 8, Large Backpack 6, Lancer 4, 8x Scope 3, Suppressor 5, Tactical Grip 3, Heavy Suppressor 3, Drum Mag 3, Talon 1 |

## Crafting

At the hideout's workbench (`scripts/crafting.gd`): instant, as many at once as your parts allow,
parts from the stash (free-kit items don't count). Crafted items aren't found in raid.

| Makes | Needs | Bench level |
|---|---|---|
| Bandage x2 | Med Parts, Duct Tape | 1 |
| Medkit | Med Parts x2, Bandage | 1 |
| Energy Drink | Water Bottle x2, Ration Pack | 1 |
| Rifle Rounds x90 | Powder Tin, Scrap Metal | 1 |
| SMG Rounds x90 | Powder Tin, Bolts x2 | 1 |
| Shotgun Shells x30 | Powder Tin, Scrap Metal | 1 |
| Sniper Rounds x20 | Powder Tin x2, Bolts x5 | 1 |
| Frag Grenade | Powder Tin x2, Scrap Metal, Duct Tape | 2 |
| Taped Grip | Scrap Metal, Duct Tape | 1 |
| Foregrip | Scrap Metal, Bolts x3, Duct Tape | 2 |
| Suppressor | Scrap Metal x3, Bolts x5, Duct Tape | 2 |
| 4x Scope | Old Phone, Bolts x3, Duct Tape | 2 |

| Bench level | Costs |
|---|---|
| 1 | free |
| 2 | $10,000, Bolts x10, Wires x3, Scrap Metal x3 |
