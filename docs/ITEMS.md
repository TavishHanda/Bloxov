# Item List

Every item in Bloxov. **Generated** from `scripts/item_db.gd` by `tools/gen_item_list.py`;
edit the item database, then re-run the script (don't edit this file by hand).

## Items

| Item | Type | Rarity | Size | Stack | Value (each) | Notes |
|---|---|---|---|---|---|---|
| Pistol (`pistol`) | Weapon | Common | 2×1 | 1 | $600 | secondary slot; semi-auto; 18 dmg, 360 rpm, 12-round mag, pistol ammo |
| AK Rifle (`ak`) | Weapon | Uncommon | 4×2 | 1 | $2,500 | primary slot; full-auto; 22 dmg, 600 rpm, 30-round mag, rifle ammo |
| Light Armor (`armor_light`) | Armor | Uncommon | 3×3 | 1 | $1,500 | -20% damage taken |
| Heavy Armor (`armor_heavy`) | Armor | Rare | 3×3 | 1 | $4,000 | -40% damage taken |
| Small Backpack (`backpack_small`) | Backpack | Common | 3×3 | 1 | $400 | 4×3 storage |
| Medium Backpack (`backpack_medium`) | Backpack | Uncommon | 3×3 | 1 | $900 | 5×4 storage |
| Large Backpack (`backpack_large`) | Backpack | Rare | 4×4 | 1 | $2,000 | 6×5 storage |
| Pistol Rounds (`pistol_ammo`) | Ammo | Common | 1×1 | 50 | $2 | full stack $100 |
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
| Rifle Rounds | 28% |
| Common valuable (Canned Beans, Duct Tape, Scrap Metal) | 28% |
| Bandage | 17% |
| Uncommon valuable (Old Phone, Car Battery) | 11% |
| Pistol Rounds | 7% |
| Medkit | 4% |
| Rare valuable (Gold Watch, Laptop) | 3% |
| Small Backpack | 2% |

### Locker (2–4 rolls)

| Entry | Chance per roll |
|---|---|
| Uncommon valuable (Old Phone, Car Battery) | 21% |
| Common valuable (Canned Beans, Duct Tape, Scrap Metal) | 15% |
| Rifle Rounds | 13% |
| Rare valuable (Gold Watch, Laptop) | 13% |
| Medkit | 10% |
| Bandage | 8% |
| Pistol Rounds | 5% |
| Pistol | 4% |
| Light Armor | 3% |
| Epic valuable (Military Chip, Antique Vase) | 3% |
| Small Backpack | 3% |
| Medium Backpack | 2% |

### Safe (1–2 rolls, loud to open)

| Entry | Chance per roll |
|---|---|
| Rare valuable (Gold Watch, Laptop) | 36% |
| Epic valuable (Military Chip, Antique Vase) | 27% |
| Uncommon valuable (Old Phone, Car Battery) | 14% |
| Legendary valuable (Rare Crystal, Golden Toilet) | 14% |
| Heavy Armor | 5% |
| Large Backpack | 4% |

### Scav (body bag, 1–3 rolls)

| Entry | Chance per roll |
|---|---|
| Rifle Rounds | 35% |
| Bandage | 18% |
| Common valuable (Canned Beans, Duct Tape, Scrap Metal) | 18% |
| Pistol Rounds | 9% |
| Uncommon valuable (Old Phone, Car Battery) | 9% |
| Medkit | 5% |
| Pistol | 4% |
| Rare valuable (Gold Watch, Laptop) | 4% |

### PMC (body bag, 1–3 rolls)

| Entry | Chance per roll |
|---|---|
| Rifle Rounds | 26% |
| Uncommon valuable (Old Phone, Car Battery) | 17% |
| Bandage | 10% |
| Medkit | 10% |
| Common valuable (Canned Beans, Duct Tape, Scrap Metal) | 10% |
| Rare valuable (Gold Watch, Laptop) | 9% |
| Pistol Rounds | 5% |
| Pistol | 4% |
| Light Armor | 4% |
| Medium Backpack | 3% |
| Epic valuable (Military Chip, Antique Vase) | 2% |
