#!/usr/bin/python

# back up json for a github org's issues/comments/releases

import os
import sys
import glob
import json
import datetime

import github

# API_BASE_URL = github.MainClass.DEFAULT_BASE_URL
API_BASE_URL = 'https://api.github.com'
RAW_DT_FMT   = '%Y-%m-%dT%H:%M:%SZ'

def rel_url_path(url):
    return url.replace(API_BASE_URL + "/", "")

def to_json(data):
    return json.dumps(data, indent=2, sort_keys=True)

def raw_to_datetime(ts):
    return datetime.datetime.strptime(ts, RAW_DT_FMT)

def datetime_to_raw(dt):
    return dt.strftime(RAW_DT_FMT)

def mkdir_p(path):
    if not os.path.exists(path):
        os.makedirs(path)

def dump_obj(obj):
    relpath = rel_url_path(obj.url)
    mkdir_p(os.path.dirname(relpath))
    jsonpath = relpath + '.json'
    if os.path.exists(jsonpath):
        tsattr = 'updated_at' if hasattr(obj,'updated_at') else 'published_at'
        updated_at = raw_to_datetime(json.load(open(jsonpath))[tsattr])
        if getattr(obj, tsattr) == updated_at:
            print "skipping already-up-to-date %s" % jsonpath
            return
    print "writing %s" % jsonpath
    json_data = to_json(obj._rawData)  # .raw_data triggers reload
    print >>open(jsonpath, "w"), json_data
    return relpath, jsonpath

def dump_org_repos(org):
    for repo in list(org.get_repos()):
        dump_repo(repo)

def dump_repo(repo):
    dump_obj(repo)
    dump_updated_obj_items(repo, "issues", state='all')
    dump_updated_obj_items(repo, "issues_comments")
    dump_updated_obj_items(repo, "pulls_comments")
    dump_updated_obj_items(repo, "pulls_review_comments")
    dump_updated_obj_items(repo, "releases")

def dump_updated_obj_items(obj, gettername, **igkw):
    upd_path = "%s/%s.ts" % (rel_url_path(obj.url), gettername)
    itemgetter = getattr(obj, "get_" + gettername)
    kw = get_since_kw(upd_path)
    kw.update(igkw)
    items = list(itemgetter(**kw))
    dump_items(items, upd_path)

def dump_items(items, updated_at_path):
    for item in items:
        dump_obj(item)
    if items:
        if hasattr(items[0], 'updated_at'):
            last_update = max( i.updated_at for i in items )
            print "writing %s" % updated_at_path
            print >>open(updated_at_path, 'w'), datetime_to_raw(last_update)
    else:
        print "no new items for %s" % updated_at_path.replace('.ts', '')

def get_since_kw(path):
    if os.path.exists(path):
        last = raw_to_datetime(open(path).read().rstrip())
        since = last + datetime.timedelta(0, 1)
        return {'since': since}
    else:
        return {}

def main(argv):
    if len(argv) == 2 and os.path.exists(argv[1]):
        org = argv[0]
        user_token = [ l.rstrip() for l in open(argv[1]) ]
        g = github.Github(*user_token)
        o = g.get_organization(org)
        dump_org_repos(o)
    else:
        print "usage: %s ORG USER_TOKEN_FILE" % os.path.basename(__file__)

if __name__ == '__main__':
    main(sys.argv[1:])

