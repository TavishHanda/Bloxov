# Item List

Every item in Bloxov. **Generated** from `scripts/item_db.gd` by `tools/gen_item_list.py`;
edit the item database, then re-run the script (don't edit this file by hand).

## Items

| Item | Type | Rarity | Size | Stack | Value (each) | Notes |
|---|---|---|---|---|---|---|
| Pistol Rounds (`pistol_ammo`) | Ammo | Common | 1×1 | 50 | $2 | full stack $100; no pistol yet (inventory step 2) |
| Rifle Rounds (`rifle_ammo`) | Ammo | Common | 1×1 | 120 | $3 | full stack $360 |
| Bandage (`bandage`) | Healing | Common | 1×1 | 5 | $100 | heals 25 over 2 s |
| Medkit (`medkit`) | Healing | Uncommon | 2×2 | 1 | $400 | heals 70 over 4 s |
| Canned Beans (`beans`) | Valuable | Common | 1×1 | 1 | $150 |  |
| Scrap Metal (`scrap`) | Valuable | Common | 2×1 | 1 | $250 |  |
| Duct Tape (`duct_tape`) | Valuable | Common | 1×1 | 1 | $300 |  |
| Old Phone (`phone`) | Valuable | Uncommon | 1×1 | 1 | $800 |  |
| Car Battery (`battery`) | Valuable | Uncommon | 2×2 | 1 | $1,200 |  |
| Gold Watch (`gold_watch`) | Valuable | Rare | 1×1 | 1 | $2,500 |  |
| Laptop (`laptop`) | Valuable | Rare | 2×1 | 1 | $4,000 |  |
| Military Chip (`mil_chip`) | Valuable | Epic | 1×1 | 1 | $7,500 |  |
| Antique Vase (`vase`) | Valuable | Epic | 2×2 | 1 | $9,000 |  |
| Rare Crystal (`crystal`) | Valuable | Legendary | 1×1 | 1 | $18,000 |  |
| Golden Toilet (`golden_toilet`) | Valuable | Legendary | 2×3 | 1 | $50,000 |  |

## Where items come from

Each container rolls a number of times; each roll picks from its table by weight.
A rarity entry (e.g. *rare*) means a random **valuable** of that rarity.
Ammo rolls come as a stack of 20–60 rifle rounds (15–40 pistol), bandages as 1–2.

### Crate (1–3 rolls)

| Entry | Chance per roll |
|---|---|
| Rifle Rounds | 31% |
| Common valuable (Canned Beans, Duct Tape, Scrap Metal) | 31% |
| Bandage | 19% |
| Uncommon valuable (Old Phone, Car Battery) | 12% |
| Medkit | 4% |
| Rare valuable (Gold Watch, Laptop) | 3% |

### Locker (2–4 rolls)

| Entry | Chance per roll |
|---|---|
| Uncommon valuable (Old Phone, Car Battery) | 25% |
| Common valuable (Canned Beans, Duct Tape, Scrap Metal) | 18% |
| Rifle Rounds | 15% |
| Rare valuable (Gold Watch, Laptop) | 15% |
| Medkit | 12% |
| Bandage | 10% |
| Epic valuable (Military Chip, Antique Vase) | 4% |

### Safe (1–2 rolls, loud to open)

| Entry | Chance per roll |
|---|---|
| Rare valuable (Gold Watch, Laptop) | 40% |
| Epic valuable (Military Chip, Antique Vase) | 30% |
| Uncommon valuable (Old Phone, Car Battery) | 15% |
| Legendary valuable (Rare Crystal, Golden Toilet) | 15% |

### Scav (body bag, 1–3 rolls)

| Entry | Chance per roll |
|---|---|
| Rifle Rounds | 40% |
| Bandage | 20% |
| Common valuable (Canned Beans, Duct Tape, Scrap Metal) | 20% |
| Uncommon valuable (Old Phone, Car Battery) | 10% |
| Medkit | 6% |
| Rare valuable (Gold Watch, Laptop) | 4% |

### PMC (body bag, 1–3 rolls)

| Entry | Chance per roll |
|---|---|
| Rifle Rounds | 31% |
| Uncommon valuable (Old Phone, Car Battery) | 20% |
| Bandage | 12% |
| Medkit | 12% |
| Common valuable (Canned Beans, Duct Tape, Scrap Metal) | 12% |
| Rare valuable (Gold Watch, Laptop) | 10% |
| Epic valuable (Military Chip, Antique Vase) | 2% |
