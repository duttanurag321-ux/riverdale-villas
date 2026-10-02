-- Riverdale Villas — Phase 1 / 004: reference data only (construction stages). No customers, no prices.
insert into construction_stages(name, sequence, requires_approval) values
 ('Booking confirmed', 1, false), ('Site preparation', 2, false), ('Excavation', 3, true),
 ('Foundation in progress', 4, false), ('Foundation completed', 5, true), ('Plinth completed', 6, true),
 ('Columns and structural work', 7, true), ('First slab / ceiling completed', 8, true), ('Brickwork completed', 9, true),
 ('Electrical and plumbing rough-in', 10, true), ('Plastering completed', 11, true), ('Flooring and fittings', 12, true),
 ('Painting and finishing', 13, true), ('Final inspection', 14, true), ('Handover completed', 15, true)
on conflict (name) do nothing;
