import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('owns the read-only chart sample table contract', () {
    final sql = File(
      'supabase/migrations/20260824020000_create_chart_sales_sample.sql',
    ).readAsStringSync().toLowerCase();

    expect(sql, contains('create table if not exists public.sales_chart'));
    expect(sql, contains('category text primary key'));
    expect(sql, contains('revenue double precision'));
    expect(sql, contains('cost double precision'));
    expect(sql, contains('sales_chart_category_not_blank'));
    expect(sql, contains('sales_chart_revenue_finite'));
    expect(sql, contains('sales_chart_cost_finite'));

    expect(
      sql,
      contains('alter table public.sales_chart enable row level security'),
    );
    expect(
      sql,
      contains(
        'revoke all on table public.sales_chart from public, anon, authenticated',
      ),
    );
    expect(
      sql,
      contains(
        'grant select on table public.sales_chart to anon, authenticated',
      ),
    );
    expect(
      sql,
      contains('create policy sales_chart_read on public.sales_chart'),
    );
    expect(sql, contains('for select'));
    expect(sql, contains('to anon, authenticated'));
    expect(sql, contains('using (true)'));
    expect(sql, isNot(contains('grant insert on table public.sales_chart')));
    expect(sql, isNot(contains('grant update on table public.sales_chart')));
    expect(sql, isNot(contains('grant delete on table public.sales_chart')));
    expect(sql, isNot(contains('for all')));

    expect(sql, contains("('q1', 120, 72)"));
    expect(sql, contains("('q4', 205, 109)"));
    expect(sql, contains('on conflict (category) do update'));
  });
}
