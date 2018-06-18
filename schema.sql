drop extension "uuid-ossp" cascade;
create extension "uuid-ossp";

drop type abac_attribute cascade;
create type abac_attribute as (
    value text,
    key text,
    namespace_id uuid
);

drop table if exists abac_subject cascade;
create table abac_subject (
    inbound abac_attribute,
    outbound abac_attribute,
    -- type text,

    primary key (inbound, outbound)
);

drop table if exists abac_object cascade;
create table abac_object (
    inbound abac_attribute,
    outbound abac_attribute,
    -- type text,

    primary key (inbound, outbound)
);

drop table if exists abac_action cascade;
create table abac_action (
    inbound abac_attribute,
    outbound abac_attribute,
    -- type text,

    primary key (inbound, outbound)
);

drop table if exists abac_policy cascade;
create table abac_policy (
    subject abac_attribute[],
    object abac_attribute[],
    action abac_attribute[],
    namespace_id uuid,

    primary key (subject, object, action, namespace_id)
);

create or replace function abac_object_target(_attrs abac_attribute[])
returns table (attr abac_attribute) as $$
    with recursive target as (
        select (outbound).value, (outbound).key, (outbound).namespace_id
            from abac_object
            where array[inbound] <@ _attrs
        union
        select (r.outbound).value, (r.outbound).key, (r.outbound).namespace_id
            from target as t
            inner join abac_object as r on r.inbound = (t.value, t.key, t.namespace_id) ::abac_attribute
    )
    select (unnest(_attrs)).*
    union
    select * from target
$$ language sql immutable;

create or replace function abac_subject_target(_attrs abac_attribute[])
returns table (attr abac_attribute) as $$
    with recursive target as (
        select (outbound).value, (outbound).key, (outbound).namespace_id
            from abac_subject
            where array[inbound] <@ _attrs
        union
        select (r.outbound).value, (r.outbound).key, (r.outbound).namespace_id
            from target as t
            inner join abac_subject as r on r.inbound = (t.value, t.key, t.namespace_id) ::abac_attribute
    )
    select (unnest(_attrs)).*
    union
    select * from target
$$ language sql immutable;

create or replace function abac_action_target(_attrs abac_attribute[])
returns table (attr abac_attribute) as $$
    with recursive target as (
        select (outbound).value, (outbound).key, (outbound).namespace_id
            from abac_action
            where array[inbound] <@ _attrs
        union
        select (r.outbound).value, (r.outbound).key, (r.outbound).namespace_id
            from target as t
            inner join abac_action as r on r.inbound = (t.value, t.key, t.namespace_id) ::abac_attribute
    )
    select (unnest(_attrs)).*
    union
    select * from target
$$ language sql immutable;

create or replace function abac_authorize(_subject abac_attribute[], _object abac_attribute[], _action abac_attribute[], _namespace_id uuid[])
returns boolean as $$
    select exists(
        select 1
            from abac_policy
            where
                subject <@ (select array_agg(distinct q) from abac_subject_target(_subject) as q)
                and object <@ (select array_agg(distinct q) from abac_object_target(_object) as q)
                and action <@ (select array_agg(distinct q) from abac_action_target(_action) as q)
                and array[namespace_id] <@ _namespace_id
            limit 1
    );
$$ language sql immutable;

create or replace function abac_object_preflight_list(_attrs abac_attribute[], _key text)
returns table (attr abac_attribute) as $$
    with recursive target as (
        select (inbound).value, (inbound).key, (inbound).namespace_id
            from abac_object
            where array[outbound] <@ _attrs
                and (inbound).key != _key
        union
        select (r.inbound).value, (r.inbound).key, (r.inbound).namespace_id
            from target as t
            inner join abac_object as r on r.outbound = (t.value, t.key, t.namespace_id) ::abac_attribute
                and (r.inbound).key != _key
    )
    select (unnest(_attrs)).*
    union
    select * from target
$$ language sql immutable;

create or replace function abac_object_preflight_array(_attrs abac_attribute[], _key text)
returns abac_attribute[] as $$
    select array_agg(t) from abac_object_preflight_list(_attrs, _key) as t;
$$ language sql immutable;

create or replace function abac_object_list_1(_attr abac_attribute, _offset integer, _limit integer)
returns table (attr abac_attribute) as $$
    select inbound
        from abac_object
        where outbound = _attr
        offset _offset
        limit _limit
$$ language sql immutable;

create or replace function abac_object_list_2(_attr1 abac_attribute, _attr2 abac_attribute, _offset integer, _limit integer)
returns table (attr abac_attribute) as $$
    select t1.inbound
        from abac_object as t1
        inner join abac_object as t2 on t1.inbound = t2.inbound
        where
            t1.outbound = _attr1
            and t2.outbound = _attr2
        offset _offset
        limit _limit
$$ language sql immutable;

create or replace function abac_object_list_3(_attr1 abac_attribute, _attr2 abac_attribute, _attr3 abac_attribute, _offset integer, _limit integer)
returns table (attr abac_attribute) as $$
    select t1.inbound
        from abac_object as t1
        inner join abac_object as t2 on t1.inbound = t2.inbound
        inner join abac_object as t3 on t1.inbound = t3.inbound
        where
            t1.outbound = _attr1
            and t2.outbound = _attr2
            and t3.outbound = _attr3
        offset _offset
        limit _limit
$$ language sql immutable;