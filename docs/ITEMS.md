# Item List

Every item in Bloxov. **Generated** from `scripts/item_db.gd` by `tools/gen_item_list.py`;
edit the item database, then re-run the script (don't edit this file by hand).

## Items

| Item | Type | Rarity | Size | Stack | Value (each) | Notes | Description |
|---|---|---|---|---|---|---|---|
| Pistol (`pistol`) | Weapon | Common | 2×1 | 1 | $600 | secondary slot; semi-auto; 17 dmg, 360 rpm, 12-round mag, pistol ammo | Small sidearm. Quick to aim, one shot per click. |
| AK Rifle (`ak`) | Weapon | Uncommon | 4×2 | 1 | $2,500 | primary slot; full-auto; 28 dmg, 600 rpm, 30-round mag, rifle ammo | Old army rifle, full auto. Hits hard, kicks harder. |
| Light Armor (`armor_light`) | Armor | Uncommon | 3×3 | 1 | $1,500 | -20% damage taken when new; 60 durability | Soft vest. Wears down as it takes hits, and protects less as it does. |
| Heavy Armor (`armor_heavy`) | Armor | Rare | 3×3 | 1 | $4,000 | -40% damage taken when new; 120 durability | Plated vest. Stops a lot, wears down as it takes hits. |
| Old Helmet (`helmet_basic`) | Helmet | Uncommon | 2×2 | 1 | $1,000 | -25% head damage taken when new; 40 durability | Dented steel pot. Better than nothing on your head. |
| Combat Helmet (`helmet_good`) | Helmet | Rare | 2×2 | 1 | $3,000 | -45% head damage taken when new; 80 durability | Army helmet. Takes a hit to the head well, wears down as it does. |
| Small Backpack (`backpack_small`) | Backpack | Common | 3×3 | 1 | $400 | 4×3 storage | A school bag. Better than pockets. |
| Medium Backpack (`backpack_medium`) | Backpack | Uncommon | 3×3 | 1 | $900 | 5×4 storage | Hiking pack with room for a good haul. |
| Large Backpack (`backpack_large`) | Backpack | Rare | 4×4 | 1 | $2,000 | 6×5 storage | Big army rucksack. Carry everything home. |
| Pistol Rounds (`pistol_ammo`) | Ammo | Common | 1×1 | 50 | $2 | full stack $100 | Pistol rounds. Loaded when you reload. |
| Rifle Rounds (`rifle_ammo`) | Ammo | Common | 1×1 | 120 | $3 | full stack $360 | Rifle rounds for the AK. Loaded when you reload. |
| Bandage (`bandage`) | Healing | Common | 1×1 | 5 | $100 | heals 25 over 2 s | Stops the bleeding. Quick to use. |
| Medkit (`medkit`) | Healing | Uncommon | 2×2 | 1 | $400 | heals 70 over 4 s | Field kit. Heals a lot, takes a while. |
| Bank Vault Key (`bank_vault_key`) | Key | Rare | 1×1 | 1 | $3,500 | opens BankVaultDoor; 5 uses | Opens the vault in the bank. 5 uses. |
| Bunker Key (`bunker_key`) | Key | Epic | 1×1 | 1 | $6,000 | opens BunkerDoor; 3 uses | Opens the bunker under the town hall. Bon keeps one on him. 3 uses. |
| Canned Beans (`beans`) | Valuable | Common | 1×1 | 1 | $150 |  | Somebody's lunch. Traders pay for food out here. |
| Water Bottle (`water`) | Valuable | Common | 1×1 | 1 | $200 |  | Clean water is rare out here. Traders pay for it. |
| Scrap Metal (`scrap`) | Valuable | Common | 2×1 | 1 | $250 |  | Bent metal. Worth a little to the right buyer. |
| Duct Tape (`duct_tape`) | Valuable | Common | 1×1 | 1 | $300 |  | Fixes everything. Sells well. |
| Ration Pack (`ration`) | Valuable | Uncommon | 1×1 | 1 | $700 |  | Novarran army meal. Tastes like cardboard, sells like gold. |
| Old Phone (`phone`) | Valuable | Uncommon | 1×1 | 1 | $800 |  | Cracked screen, still works. Someone wants the parts. |
| Car Battery (`battery`) | Valuable | Uncommon | 2×2 | 1 | $1,200 |  | Heavy and worth it. |
| Gold Watch (`gold_watch`) | Valuable | Rare | 1×1 | 1 | $2,500 |  | Somebody's pride. Now yours. |
| Cash Bundle (`cash`) | Valuable | Rare | 1×1 | 1 | $3,000 |  | Old Novarran notes. Still good with the traders. |
| Laptop (`laptop`) | Valuable | Rare | 2×1 | 1 | $4,000 |  | Novarran office laptop. The data is worth more than the machine. |
| Military Chip (`mil_chip`) | Valuable | Epic | 1×1 | 1 | $7,500 |  | Exion military hardware. Very wanted. |
| Gold Bar (`gold_bar`) | Valuable | Epic | 1×1 | 1 | $8,000 |  | Straight from the vault. |
| Antique Vase (`vase`) | Valuable | Epic | 2×2 | 1 | $9,000 |  | Old and fragile. Don't drop it. |
| Rare Crystal (`crystal`) | Valuable | Legendary | 1×1 | 1 | $18,000 |  | Nobody knows where these come from. Everyone wants one. |
| Golden Toilet (`golden_toilet`) | Valuable | Legendary | 2×3 | 1 | $50,000 |  | Yes, really. |

Armor and keys wear (durability): hits take armor points off (the damage it stopped when new), and
worn armor stops that much less; each door opened takes a use off a key, and a used-up key is gone.
Worn items are worth less: 30% of their value when worn out. Armor found in a raid is 40-100% worn.

## Where items come from

Each container rolls a number of times; each roll picks from its table by weight.
A rarity entry (e.g. *rare*) means a random **valuable** of that rarity.
A roll gives one item, except these come as a stack: Rifle Rounds 20–60, Pistol Rounds 15–40, Bandage 1–2.

### Crate (1–3 rolls)

| Entry | Chance per roll |
|---|---|
| Rifle Rounds | 28% |
| Common valuable (Canned Beans, Water Bottle, Duct Tape, Scrap Metal) | 28% |
| Bandage | 17% |
| Uncommon valuable (Ration Pack, Old Phone, Car Battery) | 11% |
| Pistol Rounds | 7% |
| Medkit | 4% |
| Rare valuable (Gold Watch, Laptop, Cash Bundle) | 3% |
| Small Backpack | 2% |

### Locker (2–4 rolls)

| Entry | Chance per roll |
|---|---|
| Uncommon valuable (Ration Pack, Old Phone, Car Battery) | 20% |
| Common valuable (Canned Beans, Water Bottle, Duct Tape, Scrap Metal) | 15% |
| Rifle Rounds | 12% |
| Rare valuable (Gold Watch, Laptop, Cash Bundle) | 12% |
| Medkit | 10% |
| Bandage | 8% |
| Pistol Rounds | 5% |
| Pistol | 4% |
| Light Armor | 3% |
| Old Helmet | 3% |
| Epic valuable (Gold Bar, Military Chip, Antique Vase) | 3% |
| Small Backpack | 2% |
| Medium Backpack | 2% |

### Safe (1–2 rolls, loud to open)

| Entry | Chance per roll |
|---|---|
| Rare valuable (Gold Watch, Laptop, Cash Bundle) | 35% |
| Epic valuable (Gold Bar, Military Chip, Antique Vase) | 26% |
| Uncommon valuable (Ration Pack, Old Phone, Car Battery) | 13% |
| Legendary valuable (Rare Crystal, Golden Toilet) | 13% |
| Heavy Armor | 5% |
| Combat Helmet | 4% |
| Large Backpack | 3% |

### Scav (body bag, 1–3 rolls)

| Entry | Chance per roll |
|---|---|
| Rifle Rounds | 35% |
| Bandage | 18% |
| Common valuable (Canned Beans, Water Bottle, Duct Tape, Scrap Metal) | 18% |
| Pistol Rounds | 9% |
| Uncommon valuable (Ration Pack, Old Phone, Car Battery) | 9% |
| Medkit | 5% |
| Pistol | 4% |
| Rare valuable (Gold Watch, Laptop, Cash Bundle) | 4% |

### Raider (body bag, 2–4 rolls)

| Entry | Chance per roll |
|---|---|
| Rifle Rounds | 27% |
| Uncommon valuable (Ration Pack, Old Phone, Car Battery) | 18% |
| Bandage | 11% |
| Medkit | 11% |
| Common valuable (Canned Beans, Water Bottle, Duct Tape, Scrap Metal) | 11% |
| Rare valuable (Gold Watch, Laptop, Cash Bundle) | 9% |
| Pistol Rounds | 5% |
| Pistol | 4% |
| Medium Backpack | 3% |
| Epic valuable (Gold Bar, Military Chip, Antique Vase) | 2% |
| Bank Vault Key | 1% |

## Loot by place

Containers in these places roll from their own table (crate, locker, safe) with these weights added,
so a gun store's lockers are mostly guns. Places not listed roll the plain tables.

| Place | Extra weights |
|---|---|
| Bunker | legendary valuable 25, epic valuable 35, Military Chip 10, Heavy Armor 10, Combat Helmet 8, AK Rifle 8, Rifle Rounds 15 |
| TownHall | Bunker Key 3, uncommon valuable 10 |
| Bank | Cash Bundle 30, Gold Bar 12, Gold Watch 15, rare valuable 10 |
| Offices | Bank Vault Key 4 |
| BigHouse1 | Gold Watch 20, Cash Bundle 15, Rare Crystal 3 |
| BigHouse2 | Laptop 15, Old Phone 25, Car Battery 10 |
| BigHouse3 | Antique Vase 15, Golden Toilet 2, epic valuable 8 |
| Police | Light Armor 15, Heavy Armor 4, Old Helmet 10, Combat Helmet 3, Pistol 15, Pistol Rounds 20, Bunker Key 2, Bank Vault Key 3 |
| GunStore | AK Rifle 12, Pistol 15, Rifle Rounds 30, Pistol Rounds 25 |
| Pharmacy | Bandage 45, Medkit 25 |
| Grocery | Canned Beans 30, Water Bottle 30, Ration Pack 10 |
| Diner | Canned Beans 30, Water Bottle 30, Ration Pack 10 |
| School | Small Backpack 15, Medium Backpack 10, Large Backpack 3, Light Armor 5, Old Helmet 5 |
