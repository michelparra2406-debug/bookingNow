-- ============================================================
-- BOOKINGNOW — Migración 002: perfil enriquecido de negocio
-- Galería de fotos (Storage), comodidades, formas de pago, horario público.
-- Ejecutar en SQL Editor DESPUÉS de schema.sql.
-- ============================================================

-- ---------- Columnas nuevas en businesses ----------
alter table businesses
  add column if not exists amenities text[] not null default '{}',        -- wifi, parking, accessible, card, kids, pets, air_conditioning, online_payment
  add column if not exists payment_methods text[] not null default '{cash,card}', -- cash, card, bizum, transfer, online
  add column if not exists languages text[] not null default '{es}',
  add column if not exists tagline text,                                   -- frase corta bajo el nombre
  add column if not exists facebook text,
  add column if not exists tiktok text,
  add column if not exists whatsapp text;

-- ---------- Galería ----------
create table if not exists business_photos (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses (id) on delete cascade,
  url text not null,
  caption text,
  sort_order int not null default 100,
  created_at timestamptz not null default now()
);
create index if not exists idx_business_photos on business_photos (business_id, sort_order);

alter table business_photos enable row level security;
drop policy if exists "photos read" on business_photos;
create policy "photos read" on business_photos for select
  using (exists (select 1 from businesses b where b.id = business_id and (b.is_published or is_member(b.id))));
drop policy if exists "photos write" on business_photos;
create policy "photos write" on business_photos for all
  using (has_role(business_id, '{owner,manager}')) with check (has_role(business_id, '{owner,manager}'));

-- ---------- Horario público (unión de los horarios del equipo) ----------
-- working_hours solo es legible por el equipo; esta función expone el horario
-- de apertura agregado para la ficha pública.
create or replace function get_public_hours(p_business uuid)
returns table (weekday int, opens time, closes time)
language sql stable security definer set search_path = public as $$
  select w.weekday::int, min(w.start_time) as opens, max(w.end_time) as closes
  from working_hours w
  join business_members m on m.id = w.member_id and m.active and m.bookable
  where w.business_id = p_business
    and exists (select 1 from businesses b where b.id = p_business and b.is_published)
  group by w.weekday
  order by w.weekday;
$$;

-- ---------- Marketplace: primera foto como portada si no hay cover ----------
-- (create or replace no admite cambiar el orden de columnas: se recrea)
drop view if exists v_marketplace;
create view v_marketplace as
select b.id, b.slug, b.name, b.sector_id, s.name_es as sector_name, b.description, b.tagline,
       b.logo_url,
       coalesce(b.cover_url, (select p.url from business_photos p where p.business_id = b.id order by p.sort_order, p.created_at limit 1)) as cover_url,
       b.rating_avg, b.rating_count, b.amenities,
       l.city, l.address, l.lat, l.lng,
       (select min(price_cents) from services sv where sv.business_id = b.id and sv.active and sv.online_bookable) as min_price_cents,
       (select count(*) from services sv where sv.business_id = b.id and sv.active) as services_count,
       (select count(*) from business_photos p where p.business_id = b.id) as photos_count
from businesses b
join sectors s on s.id = b.sector_id
left join locations l on l.business_id = b.id and l.is_default
where b.is_published and b.online_booking_enabled;
alter view v_marketplace set (security_invoker = true);

-- ---------- Storage: bucket público para fotos de negocios ----------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('business-media', 'business-media', true, 8388608, '{image/jpeg,image/png,image/webp}')
on conflict (id) do update set public = true, file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Ruta de los objetos: <business_id>/<archivo>. Solo owner/manager del negocio
-- pueden subir o borrar; lectura pública.
drop policy if exists "business media read" on storage.objects;
create policy "business media read" on storage.objects for select
  using (bucket_id = 'business-media');
drop policy if exists "business media write" on storage.objects;
create policy "business media write" on storage.objects for insert
  with check (bucket_id = 'business-media'
    and has_role((storage.foldername(name))[1]::uuid, '{owner,manager}'));
drop policy if exists "business media update" on storage.objects;
create policy "business media update" on storage.objects for update
  using (bucket_id = 'business-media'
    and has_role((storage.foldername(name))[1]::uuid, '{owner,manager}'));
drop policy if exists "business media delete" on storage.objects;
create policy "business media delete" on storage.objects for delete
  using (bucket_id = 'business-media'
    and has_role((storage.foldername(name))[1]::uuid, '{owner,manager}'));

-- ---------- Datos de demo: fotos, comodidades y redes ----------
do $$
declare v_marta uuid; v_fisio uuid;
begin
  select id into v_marta from businesses where slug = 'studio-marta';
  select id into v_fisio from businesses where slug = 'fisio-vital';

  if v_marta is not null then
    update businesses set
      tagline = 'Color, corte y cuidado capilar en el centro de Madrid',
      cover_url = 'https://images.unsplash.com/photo-1560066984-138dadb4c035?w=1600&q=80',
      logo_url = 'https://images.unsplash.com/photo-1562322140-8baeececf3df?w=400&q=80',
      amenities = '{wifi,card,accessible,air_conditioning,online_payment}',
      payment_methods = '{cash,card,bizum}',
      instagram = 'studiomarta', whatsapp = '+34600111222', website = 'https://studiomarta.example'
    where id = v_marta;
    delete from business_photos where business_id = v_marta;
    insert into business_photos (business_id, url, caption, sort_order) values
      (v_marta, 'https://images.unsplash.com/photo-1560066984-138dadb4c035?w=1600&q=80', 'El salón', 1),
      (v_marta, 'https://images.unsplash.com/photo-1522337660859-02fbefca4702?w=1600&q=80', 'Zona de color', 2),
      (v_marta, 'https://images.unsplash.com/photo-1521590832167-7bcbfaa6381f?w=1600&q=80', 'Balayage', 3),
      (v_marta, 'https://images.unsplash.com/photo-1519699047748-de8e457a634e?w=1600&q=80', 'Corte y peinado', 4),
      (v_marta, 'https://images.unsplash.com/photo-1600948836101-f9ffda59d250?w=1600&q=80', 'Lavacabezas', 5);
    update business_members set avatar_url = 'https://images.unsplash.com/photo-1580489944761-15a19d654956?w=400&q=80'
      where business_id = v_marta and role = 'owner';
    update business_members set avatar_url = 'https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=400&q=80'
      where business_id = v_marta and display_name = 'Lucía Fernández';
  end if;

  if v_fisio is not null then
    update businesses set
      tagline = 'Fisioterapia deportiva y readaptación',
      cover_url = 'https://images.unsplash.com/photo-1519824145371-296894a0daa9?w=1600&q=80',
      logo_url = 'https://images.unsplash.com/photo-1576091160550-2173dba999ef?w=400&q=80',
      amenities = '{wifi,parking,accessible,air_conditioning}',
      payment_methods = '{cash,card,bizum,transfer}',
      instagram = 'fisiovital', whatsapp = '+34600333444'
    where id = v_fisio;
    delete from business_photos where business_id = v_fisio;
    insert into business_photos (business_id, url, caption, sort_order) values
      (v_fisio, 'https://images.unsplash.com/photo-1519824145371-296894a0daa9?w=1600&q=80', 'Sala de tratamiento', 1),
      (v_fisio, 'https://images.unsplash.com/photo-1571019614242-c5c5dee9f50b?w=1600&q=80', 'Readaptación', 2),
      (v_fisio, 'https://images.unsplash.com/photo-1544367567-0f2fcb009e0b?w=1600&q=80', 'Pilates terapéutico', 3),
      (v_fisio, 'https://images.unsplash.com/photo-1629909613654-28e377c37b09?w=1600&q=80', 'Recepción', 4);
    update business_members set avatar_url = 'https://images.unsplash.com/photo-1612349317150-e413f6a5b16d?w=400&q=80'
      where business_id = v_fisio and role = 'owner';
  end if;
end $$;
