#!/usr/bin/python

# back up json for a github org's issues/comments/releases

import os
import sys
import glob
import json
import datetime
import operator

import github

API_BASE_URL = 'https://api.github.com'
RAW_DT_FMT   = '%Y-%m-%dT%H:%M:%SZ'

# sigh - the github api doesn't return a url for pull reviews
if not hasattr(github.PullRequestReview.PullRequestReview, 'url'):
    def prr_url(obj): return "%s/reviews/%s" % (obj.pull_request_url, obj.id)
    github.PullRequestReview.PullRequestReview.url = property(prr_url)

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
        if json.load(open(jsonpath)) == obj._rawData:
            print "skipping already-up-to-date %s" % jsonpath
            return
    print "writing %s" % jsonpath
    json_data = to_json(obj._rawData)  # .raw_data triggers reload
    print >>open(jsonpath, "w"), json_data
    return True

def dump_org_repos(org):
    repos = sorted(org.get_repos(), key=operator.attrgetter('name'))
    for i,repo in enumerate(repos):
        print "(%s/%s) [%s]" % (i+1, len(repos), repo.name)
        dump_repo(repo)

def dump_repo(repo):
    dump_obj(repo)
    updated_issues = dump_updated_obj_items(repo, "issues", state='all')
    updated_pulls = [ repo.get_pull(ui.number) for ui in updated_issues
                      if 'pull_request' in ui._rawData ]
    dump_items(updated_pulls, nest="reviews")
    dump_updated_obj_items(repo, "issues_comments")
    dump_updated_obj_items(repo, "pulls_comments")
    dump_updated_obj_items(repo, "releases")

def dump_updated_obj_items(obj, gettername, nest=None, **igkw):
    updated_at_path = "%s/%s.ts" % (rel_url_path(obj.url), gettername)
    itemgetter = getattr(obj, "get_" + gettername)
    kw = get_since_kw(updated_at_path, itemgetter)
    kw.update(igkw)
    items = list(itemgetter(**kw))
    return dump_items(items, updated_at_path, nest, 'since' in kw)

def dump_items(items, updated_at_path=None, nest=None, want_since=False):
    updated_items = filter(dump_obj, items)
    if nest:
        for item in updated_items:
            dump_updated_obj_items(item, nest)
    if updated_items and want_since:
        if hasattr(items[0], 'updated_at'):
            last_update = max( i.updated_at for i in items )
            print "writing %s" % updated_at_path
            print >>open(updated_at_path, 'w'), datetime_to_raw(last_update)
    elif updated_at_path:
        print "no new items for %s" % updated_at_path.replace('.ts', '')
    return updated_items

def get_since_kw(path, itemgetter):
    want_since = ':param since:' in itemgetter.__doc__  # yikes...
    if want_since and os.path.exists(path):
        last = raw_to_datetime(open(path).read().rstrip())
        since = last + datetime.timedelta(0, 1)
        return {'since': since}
    else:
        return {}

def main(argv):
    if len(argv) == 2 and os.path.exists(argv[1]):
        org = argv[0]
        user_token = [ l.rstrip() for l in open(argv[1]) ]
        g = github.Github(*user_token, timeout=60)
        print "rate_limiting api queries remaining: %s/%s" % g.rate_limiting
        print "---"
        o = g.get_organization(org)
        dump_org_repos(o)
    else:
        print "usage: %s ORG USER_TOKEN_FILE" % os.path.basename(__file__)

if __name__ == '__main__':
    main(sys.argv[1:])

