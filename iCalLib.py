import datetime
import urllib
import re
import os
import sys

# created by Nick Pasternack to help VDT (4/8/12)

class CalEvent:
    def __init__(self, summary, start_date, end_date=None):
        """This is the Constructor for the CalEvent Class, 
        it has three attributes: summary, start_date, and end_date 
        (all passed as parameters).  If end_date is not given, 
        it will default to start_date.
        """
        # if end_date doesn't have a value, give it start date
        if end_date is None:
            end_date = start_date
        # typecheck
        if not isinstance(summary, str):
            raise TypeError("summary needs to be a string")
        elif not isinstance(start_date, datetime.date):
            raise TypeError("start_date needs to be a datetime.date")
        elif not isinstance(end_date, datetime.date):
            raise TypeError("end_date needs to be a datetime.date")
        
        self.summary = summary
        self.start_date = start_date
        self.end_date = end_date

    def occurs_on_day(self,date):
        """Returns True if the event occurs on the date (datetime.date) 
        passed as a parameter (False otherwise)
        """
        if not isinstance(date, datetime.date):
            raise TypeError("date should be a datetime.date")
        return (date >= self.start_date and date <= self.end_date)
        
class Cal:
    def __init__(self):
        """This is the constructor for the Cal class, there are no 
        parameters.
        """
        self.events = []
        
        
    def download(self, url):
        """This method downloads an ical file (it makes sure you are in  
        fact downloading an ical file) from a given url to
        whatever directory this script is in and names it "ical.ics"
        """
        if not re.search("\.ics$", url):
            raise ValueError("url must be link to .ics file")
        
        try:
            icfile = urllib.urlretrieve(url)
            print "Downloaded calendar successfully"
        except IOError:
            print "Downloaded unsuccessful"
            raise
        ical_file = icfile[0]
            
        self.parse_for_events(ical_file)
        
    def add_event(self,event):
        """Adds contents of a CalEvent (event) passed as a parameter"""
        
        if not isinstance(event, CalEvent):
            raise TypeError("event should be a CalEvent")
        
        self.events.append(event)
        
    def parse_for_events(self, ical_file):
        """Parses the ical file for events"""
        start_date = None
        end_date = None
        summary = None
        in_event = False

        ical_fh = open(ical_file, "r")
        for line in ical_fh:
            
            if re.search('BEGIN:VEVENT',line):
                in_event = True
                continue
            elif re.search('END:VEVENT',line):
                in_event = False
                continue

            if in_event:
                if re.search('DTSTART',line):
                    value_match = re.search(r':(\d+)',line)
                    start_date = value_match.group(1)
                if re.search('DTEND',line):
                    value_match = re.search(r':(\d+)',line)
                    end_date = value_match.group(1)
                if re.search('SUMMARY',line):
                    value_match = re.search(r':(.+)',line)
                    summary = value_match.group(1)
                
            if start_date is not None and end_date is not None and summary is not None:
                start_date_year = int(start_date[0:4])
                start_date_month = int(start_date[4:6])
                start_date_day = int(start_date[6:8])
                start_date_obj = datetime.date(start_date_year, start_date_month, start_date_day)
                end_date_year = int(end_date[0:4])
                end_date_month = int(end_date[4:6])
                end_date_day = int(end_date[6:8])
                end_date_obj = datetime.date(end_date_year, end_date_month, end_date_day)
                self.add_event(CalEvent(summary, start_date_obj, end_date_obj))
                start_date = None
                end_date = None
                summary = None
                

    def events_on_date(self,date):
        """Return events on a given datetime.date in a list"""
        ret = []
        for event in self.events:
            if event.occurs_on_day(date):
                ret.append(event)
        if not ret:
            # if list is empty
            print "no events found for that date"
        else:
            return ret
            
    def events_today(self):
        """Return events today in a list"""
        return self.events_on_date(datetime.date.today())
                
    def print_events(self):
        """Prints the list of events"""
        for event in self.events:
            print event
        
        

            
        
