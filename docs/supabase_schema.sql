-- Serving — Postgres / Supabase schema
--
-- Matches the models in Serving/Core/Models. Django owns writes through DRF;
-- this file is the starting point for the initial migration.

create extension if not exists "uuid-ossp";
create extension if not exists postgis;   -- for nearby-stringer search

-- ---------------------------------------------------------------- enums

create type account_type      as enum ('business', 'player');
create type location_kind     as enum ('storefront', 'residential', 'publicMeetingSpot');
create type racquet_sport     as enum ('tennis', 'badminton');
create type string_category   as enum ('polyester', 'multifilament', 'syntheticGut',
                                       'naturalGut', 'hybrid', 'badminton');
create type order_status      as enum ('awaitingBusiness', 'awaitingPlayerApproval',
                                       'confirmed', 'inProgress', 'complete',
                                       'pickedUp', 'declined', 'cancelled');
create type payment_method    as enum ('applePay', 'card', 'payPal');
create type payment_state     as enum ('requiresPaymentMethod', 'requiresConfirmation',
                                       'processing', 'succeeded', 'failed', 'refunded');
create type payout_status     as enum ('notConnected', 'pendingVerification',
                                       'active', 'paused');
create type string_kind       as enum ('storefront', 'byos');

-- ---------------------------------------------------------------- accounts

create table app_user (
    id              uuid primary key default uuid_generate_v4(),
    email           citext not null unique,
    account_type    account_type not null,
    display_name    text not null,
    owner_name      text,
    phone           text not null,
    phone_verified  boolean not null default false,
    business_id     uuid,                       -- fk added after business exists
    avatar_url      text,
    -- Django auth owns the password hash; kept here for a single-table read
    password_hash   text,
    created_at      timestamptz not null default now(),
    updated_at      timestamptz not null default now()
);

create table phone_verification (
    id          uuid primary key default uuid_generate_v4(),
    phone       text not null,
    code_hash   text not null,
    attempts    int not null default 0,
    expires_at  timestamptz not null,
    verified_at timestamptz,
    created_at  timestamptz not null default now()
);

create index on phone_verification (phone, created_at desc);

create table device_token (
    id          uuid primary key default uuid_generate_v4(),
    user_id     uuid not null references app_user(id) on delete cascade,
    token       text not null unique,
    platform    text not null default 'ios',
    created_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------- businesses

create table business (
    id                            uuid primary key default uuid_generate_v4(),
    owner_user_id                 uuid references app_user(id) on delete set null,
    name                          text not null,
    owner_name                    text not null default '',
    phone                         text not null default '',

    address_line1                 text not null default '',
    address_line2                 text not null default '',
    address_city                  text not null default '',
    address_state                 text not null default '',
    address_postal_code           text not null default '',
    location                      geography(point, 4326),
    location_kind                 location_kind not null default 'storefront',

    -- false for shops sourced from map data that have not signed up. Those
    -- rows carry name / address / phone only, and the app shows a call button
    -- instead of a storefront.
    is_claimed                    boolean not null default false,

    about                         text not null default '',
    rating                        numeric(2,1),
    rating_count                  int not null default 0,
    typical_turnaround_hours      int not null default 48,
    accepts_bring_your_own_string boolean not null default true,
    bring_your_own_string_fee     numeric(10,2) not null default 0,
    drop_off_instructions         text not null default '',

    stripe_account_id             text,
    payout_status                 payout_status not null default 'notConnected',

    created_at                    timestamptz not null default now(),
    updated_at                    timestamptz not null default now()
);

alter table app_user
    add constraint app_user_business_fk
    foreign key (business_id) references business(id) on delete set null;

create index business_location_idx on business using gist (location);
create index business_claimed_idx  on business (is_claimed);

create table business_open_hours (
    id                 uuid primary key default uuid_generate_v4(),
    business_id        uuid not null references business(id) on delete cascade,
    weekday            int not null check (weekday between 1 and 7),  -- 1 = Sunday
    opens_at_minutes   int not null default 600,
    closes_at_minutes  int not null default 1140,
    is_closed          boolean not null default false,
    unique (business_id, weekday)
);

create table stringing_service (
    id                uuid primary key default uuid_generate_v4(),
    business_id       uuid not null references business(id) on delete cascade,
    name              text not null,
    details           text not null default '',
    labor_price       numeric(10,2) not null check (labor_price >= 0),
    turnaround_hours  int not null default 48,
    is_active         boolean not null default true,
    created_at        timestamptz not null default now()
);

create table string_product (
    id           uuid primary key default uuid_generate_v4(),
    business_id  uuid not null references business(id) on delete cascade,
    brand        text not null,
    name         text not null,
    category     string_category not null,
    sport        racquet_sport not null default 'tennis',
    gauge        text not null default '',
    price        numeric(10,2) not null check (price >= 0),
    stock_count  int not null default 0 check (stock_count >= 0),
    details      text not null default '',
    is_active    boolean not null default true,
    created_at   timestamptz not null default now()
);

create index string_product_business_idx on string_product (business_id, is_active);

-- ---------------------------------------------------------------- orders

create table stringing_order (
    id                     uuid primary key default uuid_generate_v4(),
    order_number           text not null unique,

    business_id            uuid not null references business(id) on delete restrict,
    player_id              uuid not null references app_user(id) on delete restrict,
    service_id             uuid references stringing_service(id) on delete set null,
    service_name           text not null default 'Stringing',

    -- Denormalised so a historical receipt never changes when a shop edits
    -- its profile or pricing.
    business_name          text not null,
    business_phone         text not null default '',
    player_name            text not null,
    player_phone           text not null default '',
    drop_off_line1         text not null default '',
    drop_off_line2         text not null default '',
    drop_off_city          text not null default '',
    drop_off_state         text not null default '',
    drop_off_postal_code   text not null default '',
    drop_off_instructions  text not null default '',

    drop_off_date          timestamptz not null,
    proposed_pick_up_date  timestamptz,
    confirmed_pick_up_date timestamptz,
    business_note          text,

    strings_subtotal            numeric(10,2) not null default 0,
    labor_subtotal              numeric(10,2) not null default 0,
    bring_your_own_string_fee   numeric(10,2) not null default 0,
    service_fee                 numeric(10,2) not null default 0,
    stringer_commission         numeric(10,2) not null default 0,  -- not in total
    tax                         numeric(10,2) not null default 0,
    total                       numeric(10,2) generated always as
        (strings_subtotal + labor_subtotal + bring_your_own_string_fee + service_fee + tax) stored,

    payment_method         payment_method not null default 'applePay',
    payment_state          payment_state not null default 'requiresPaymentMethod',
    stripe_payment_intent  text,
    charged_at             timestamptz,
    card_last4             text,

    status                 order_status not null default 'awaitingBusiness',
    created_at             timestamptz not null default now(),
    updated_at             timestamptz not null default now(),

    -- The pick-up time is only "confirmed" once the player has accepted it,
    -- which is the same moment payment is captured.
    constraint confirmed_requires_pick_up
        check (status not in ('confirmed', 'inProgress', 'complete', 'pickedUp')
               or confirmed_pick_up_date is not null),
    constraint confirmed_requires_payment
        check (status not in ('confirmed', 'inProgress', 'complete', 'pickedUp')
               or payment_state in ('succeeded', 'refunded'))
);

create index order_business_idx on stringing_order (business_id, status, created_at desc);
create index order_player_idx   on stringing_order (player_id, created_at desc);
create index order_pickup_idx   on stringing_order (business_id, confirmed_pick_up_date);

create table order_racquet (
    id              uuid primary key default uuid_generate_v4(),
    order_id        uuid not null references stringing_order(id) on delete cascade,
    sport           racquet_sport not null default 'tennis',
    model           text not null default '',
    main_tension    numeric(4,1) not null,
    cross_tension   numeric(4,1) not null,
    notes           text not null default '',

    -- 'storefront' rows carry product_id/product_name/string_price;
    -- 'byos' rows carry byos_description.
    string_kind        string_kind not null,
    product_id         uuid references string_product(id) on delete set null,
    product_name       text,
    string_price       numeric(10,2) not null default 0,
    byos_description   text not null default '',

    constraint storefront_needs_product
        check (string_kind <> 'storefront' or product_name is not null)
);

create index order_racquet_order_idx on order_racquet (order_id);

-- ---------------------------------------------------------------- payouts

create table payout (
    id            uuid primary key default uuid_generate_v4(),
    business_id   uuid not null references business(id) on delete cascade,
    amount        numeric(10,2) not null,
    stripe_payout text,
    status        text not null default 'pending',
    paid_at       timestamptz,
    created_at    timestamptz not null default now()
);

create index payout_business_idx on payout (business_id, created_at desc);

-- ---------------------------------------------------------------- helpers

-- Nearby search backing GET /businesses/search/
create or replace function businesses_near(
    lat double precision,
    lng double precision,
    radius_m double precision default 25000
)
returns setof business
language sql stable as $$
    select *
    from business
    where location is null
       or st_dwithin(location, st_makepoint(lng, lat)::geography, radius_m)
    order by
        case when location is null then 1 else 0 end,
        st_distance(location, st_makepoint(lng, lat)::geography);
$$;

create or replace function touch_updated_at() returns trigger
language plpgsql as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

create trigger app_user_touch      before update on app_user
    for each row execute function touch_updated_at();
create trigger business_touch      before update on business
    for each row execute function touch_updated_at();
create trigger order_touch         before update on stringing_order
    for each row execute function touch_updated_at();
