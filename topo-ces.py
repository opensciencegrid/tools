#!/usr/bin/python

from __future__ import print_function

import collections
import operator
import sys
import os

try: 
    from urllib.request import urlopen 
except ImportError: 
    from urllib2 import urlopen 

import xml.etree.ElementTree as et

_rgsummary_url = 'https://topology.opensciencegrid.org/rgsummary/xml'
_ce_params = [
    ('gridtype',     'on'),
    ('gridtype_1',   'on'),
    ('active',       'on'),
    ('active_value', '1' ),
    ('service_1',    'on')
]
_ces_url = "%s?%s" % (_rgsummary_url, '&'.join(map('='.join, _ce_params)))


# autodict is a defaultdict returning a new autodict for missing keys. 
# __add__ allows `d[k] += v` to work automatically before `d` contains `k`. 
class autodict(collections.defaultdict): 
    def __init__(self,*other): 
        collections.defaultdict.__init__(self, self.__class__, *other) 
    def __add__ (self, other): 
        return other 
    def __repr__(self): 
        return dict.__repr__(self)


def rg_info(rg):
    facility = rg.find('Facility').find('Name').text
    site = rg.find('Site').find('Name').text
    resources = [ (facility, site, r.find('Name').text, r.find('FQDN').text,
                      resource_services(r))
                  for r in rg.find('Resources').findall('Resource') ]
    return resources

def resource_services(r):
    return set( s.find('Name').text
                for s in r.find('Services').findall('Service') )

def get_ce_resource_tree(xmltxt, exclude=None):
    #xmltxt = urlopen(_ces_url).read()
    xmltree = et.fromstring(xmltxt)
    ad = autodict()
    for rg in xmltree.findall('ResourceGroup'):
        for facility, site, resource, fqdn, services in rg_info(rg):
            if 'CE' in services:
                if exclude is None or resource not in exclude[facility][site]:
                    ad[facility][site][resource] = fqdn
    return ad


def print_resource_tree(ad):
    for facility_name, facility_ad in sorted(ad.items()):
        print("Facility: %s" % facility_name)
        for site_name, site_ad in sorted(facility_ad.items()):
            print("  Site: %s" % site_name)
            for resource_name, fqdn in sorted(site_ad.items()):
                print("    Resource: %s (%s)" % (fqdn, resource_name))
            print()


def readfile(path):
    return open(path).read()

_usage = """\
Usage:

$ {script} --getxml > ce_resources.xml  # dump current xml for CE resources
$ {script} ce_resources.xml             # print resource hierarchy
$ {script} old.xml new.xml              # same but exclude old resources
"""

def usage():
    script = os.path.basename(__file__)
    print(_usage.format(script=script))


def main(args):
    if args == ['--getxml']:
        print(urlopen(_ces_url).read())
    elif len(args) == 1:
        ad = get_ce_resource_tree(readfile(args[0]))
        print_resource_tree(ad)
    elif len(args) == 2:
        exclude_ad = get_ce_resource_tree(readfile(args[0]))
        new_ad     = get_ce_resource_tree(readfile(args[1]), exclude_ad)
        print_resource_tree(new_ad)
    else:
        usage()


if __name__ == '__main__':
    main(sys.argv[1:])


