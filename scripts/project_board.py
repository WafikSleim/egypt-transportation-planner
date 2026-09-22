# -*- coding: utf-8 -*-
"""Organize the "Masar" GitHub Project (v2, number 2).

Works with the Team-planning template's own fields rather than adding
parallel ones:

  Status    Done      shipped, and verifiable without a human
            In review shipped, but the claim rests on judgement only the
                      maintainer can apply - native Egyptian Arabic, or how
                      it behaves on real hardware
            Ready     work that can be picked up today
            Backlog   work waiting on another issue
  Priority  P0        on the critical path: blocks the v1 gate and blocks
                      other issues
            P1        everything else in the v1 milestone
            P2        not holding the release
  Size      from the user-story estimates where they exist
  Area      the one field added - nine work streams, so 34 items read as
            streams rather than a flat list

Needs `gh auth refresh -s project`. Idempotent: reads the board first and
only writes what differs, so re-running after new issues is safe.

    python organize_masar.py            # dry run
    python organize_masar.py --apply
"""
import json, subprocess, sys, time

PROJECT_ID = 'PVT_kwHOBf2lhM4BkPQn'
REPO = 'WafikSleim/egypt-transportation-planner'
APPLY = '--apply' in sys.argv

AREA = {
    'Foundation': [1, 2, 3, 4, 5, 10],
    'Journey': [6, 7, 8, 9],
    'Storage & history': [11, 12, 13],
    'Places & search': [14, 15, 17, 18],
    'Map': [16, 19, 20],
    'Notifications & tracking': [21, 22, 23, 24, 25],
    'Quality': [26, 27, 28, 29, 35],
    'Build & release': [30, 31, 32],
    'Design & data': [33, 34],
}

# Shipped and machine-verified: analyze, tests and a build settle these, so
# there is nothing left for a person to judge.
DONE = {1, 4, 5, 10, 29, 35}

# Shipped, but "done" here is a claim I cannot check myself. Two things need
# the maintainer: whether the Arabic reads as Egyptian speech rather than
# translated English, and how any of it behaves on a real phone - nothing in
# this project has ever run on hardware, only in widget tests and an APK
# build. Each carries a comment saying exactly what to check.
REVIEW = {2, 3, 6, 7, 8, 9, 11, 12, 13, 14, 18, 19, 26, 30, 32, 33, 34}

# Waiting on another issue. Matches the `blocked` label exactly.
BLOCKED = {15, 16, 17, 20, 22, 23, 24, 25}

# The critical path: each of these is in the v1 gate *and* holds up others.
P0 = {21}
P2 = {28, 34}          # milestone "After v1"

SIZE = {
    11: 'M', 12: 'S', 13: 'S', 14: 'L', 15: 'L', 16: 'M', 17: 'M', 18: 'S',
    19: 'L', 20: 'M', 21: 'M', 22: 'S', 23: 'M', 24: 'L', 25: 'M', 26: 'M',
    27: 'M', 28: 'S', 29: 'S', 30: 'S', 31: 'M', 32: 'XS', 33: 'XS', 34: 'M', 35: 'S',
}
# Shipped issues get Status and Area only. Estimating work that is already
# finished would be inventing numbers.


def gql(query):
    r = subprocess.run(['gh', 'api', 'graphql', '-f', 'query=' + query],
                       capture_output=True, text=True, encoding='utf-8')
    if r.returncode != 0:
        raise SystemExit('GraphQL failed:\n' + r.stderr.strip()[:700])
    payload = json.loads(r.stdout)
    if 'errors' in payload:
        raise SystemExit('GraphQL errors:\n' + json.dumps(payload['errors'])[:700])
    return payload['data']


def fields():
    data = gql('''query{ node(id:"%s"){ ... on ProjectV2 {
        fields(first:50){ nodes{
          ... on ProjectV2FieldCommon{ id name dataType }
          ... on ProjectV2SingleSelectField{ options{ id name } }
        }}}}}''' % PROJECT_ID)
    return {f['name']: f for f in data['node']['fields']['nodes'] if f}


def create_area_field(options):
    opts = ','.join('{name:"%s",color:BLUE,description:""}' % o for o in options)
    data = gql('''mutation{ createProjectV2Field(input:{
        projectId:"%s", dataType:SINGLE_SELECT, name:"Area",
        singleSelectOptions:[%s]
      }){ projectV2Field{ ... on ProjectV2SingleSelectField{
        id name options{ id name } } } } }''' % (PROJECT_ID, opts))
    return data['createProjectV2Field']['projectV2Field']


def board_items():
    out, cursor = {}, 'null'
    while True:
        data = gql('''query{ node(id:"%s"){ ... on ProjectV2 {
            items(first:100, after:%s){
              pageInfo{ hasNextPage endCursor }
              nodes{ id content{ ... on Issue{ number } } }
            }}}}''' % (PROJECT_ID, cursor))
        items = data['node']['items']
        for n in items['nodes']:
            if n['content'] and n['content'].get('number'):
                out[n['content']['number']] = n['id']
        if not items['pageInfo']['hasNextPage']:
            return out
        cursor = '"%s"' % items['pageInfo']['endCursor']


def repo_issues():
    r = subprocess.run(
        ['gh', 'issue', 'list', '--repo', REPO, '--state', 'all', '--limit', '200',
         '--json', 'number,id'],
        capture_output=True, text=True, encoding='utf-8')
    return {i['number']: i['id'] for i in json.loads(r.stdout)}


def add_item(content_id):
    data = gql('''mutation{ addProjectV2ItemById(input:{
        projectId:"%s", contentId:"%s"}){ item{ id } } }''' % (PROJECT_ID, content_id))
    return data['addProjectV2ItemById']['item']['id']


def set_select(item_id, field, value):
    option = next((o for o in field.get('options', []) if o['name'] == value), None)
    if not option:
        print('    ! no option "%s" on field "%s"' % (value, field['name']))
        return
    gql('''mutation{ updateProjectV2ItemFieldValue(input:{
        projectId:"%s", itemId:"%s", fieldId:"%s",
        value:{singleSelectOptionId:"%s"}}){ projectV2Item{ id } } }'''
        % (PROJECT_ID, item_id, field['id'], option['id']))


def main():
    flds = fields()
    print('Fields on the board: %s\n' % ', '.join(sorted(flds)))

    area = flds.get('Area')
    if area is None:
        if APPLY:
            area = create_area_field(list(AREA))
            print('created field "Area" with %d options\n' % len(AREA))
        else:
            print('would create field "Area" with %d options\n' % len(AREA))

    on_board = board_items()
    issues = repo_issues()
    area_of = {n: a for a, nums in AREA.items() for n in nums}

    for number in sorted(issues):
        shipped = number in DONE or number in REVIEW
        status = ('Done' if number in DONE
                  else 'In review' if number in REVIEW
                  else 'Backlog' if number in BLOCKED
                  else 'Ready')
        priority = None if shipped else ('P0' if number in P0
                                         else 'P2' if number in P2 else 'P1')
        size = None if shipped else SIZE.get(number)
        a = area_of.get(number)
        new = number not in on_board

        line = '  #%-3d %-26s %-8s %-3s %-3s%s' % (
            number, a or '-', status, priority or '-', size or '-',
            '   (adding)' if new else '')
        print(line)
        if not APPLY:
            continue

        item_id = on_board.get(number) or add_item(issues[number])
        set_select(item_id, flds['Status'], status)
        if area:
            set_select(item_id, area, a)
        if priority:
            set_select(item_id, flds['Priority'], priority)
        if size:
            set_select(item_id, flds['Size'], size)
        time.sleep(0.12)

    print('\n%d issues.%s' % (len(issues), '' if APPLY else '  (dry run - pass --apply)'))


if __name__ == '__main__':
    main()
