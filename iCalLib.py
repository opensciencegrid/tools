import datetime
import urllib
import re
import os,sys

# created by Nick Pasternack to help VDT (4/8/12)

class CalEvent:
	def __init__(self, description, start_date, end_date=''):
		"""This is the Constructor for the CalEvent Class, 
		it has three attributes: description, start_date, and end_date 
		(all passed as parameters).  If end-date is not given, 
		it will default to start_date.
		"""
		# if end_date doesn't have a value, give it start date
		if end_date == '':
			end_date = start_date
		# typecheck
		if isinstance(description, str) != True:
			raise TypeError("Description needs to be a string")
		elif isinstance(start_date, datetime.date) != True:
			raise TypeError("Start Date needs to be a datetime.date")
		elif isinstance(end_date, datetime.date) != True:
			raise TypeError("End Date needs to be a datetime.date")
		else:
			pass
		
		self.description = description
		self.start_date = start_date
		self.end_date = end_date
	def occurs_on_day(self,date):
		"""Returns True if the event occurs on the date (datetime.date) 
		passed as a parameter (False otherwise)
		"""
		if isinstance(date, datetime.date) == True:
			pass
		else:
			raise TypeError("date should be a datetime.date")
		if date >= self.start_date and date <= self.end_date:
			return True
		else:
			return False
		
class Cal:
	def __init__(self):
		"""This is the constructor for the Cal class, there are no 
		parameters.
		"""
		self.today = datetime.datetime.now() # for events_today
		self.dictionary = [] # for storing multiple events
		self.isItAnEvent = False # see if we are in an event
		self.eventsOnDate = []
		self.eventsToday = []
		self.summary = ''
		self.start_date = None
		self.end_date = None
		
		
	def download(self,URL):
		"""This method downloads an ical file (it makes sure you are in  
		fact downloading an ical file) from a given url to
		whatever directory this script is in and names it "ical.ics"
		"""
		self.url = URL
		isIcsFile = re.search("\.ics",self.url)
		if isIcsFile == None:
			raise IOError("url must be link to .ics file")
		
		try:
			icfile = urllib.urlretrieve(self.url)
			print "Downloaded calendar successfully"
		except IOError:
			raise IOError("Downloaded unsuccessful")
		ical_file = icfile[0]
			
		self.parseForEvents(ical_file)
		
	def add_event(self,event):
		"""Adds contents of a CalEvent (event) passed as a parameter"""
		
		if isinstance(event, CalEvent) != True:
			raise TypeError("Event should be a CalEvent")
		
		self.dictionary.append(event)
		
	def parseForEvents(self, ical_file):
		"""Parses the ical file for events"""
		ical_file = open(ical_file, "r").readlines() # icalfile text
		self.start_date = None
		self.end_date = None
		self.summary = None
		for line in ical_file:
			
			m = re.search('BEGIN:VEVENT',line)
			m2 = re.search('END:VEVENT',line)
			if m != None:
				self.isItAnEvent = True
			if self.isItAnEvent == True:
				m2 = re.search('DTSTART',line)
				if m2 != None:
					m3 = re.search(r'(?<=:)\d+',line)
					self.start_date = m3.group(0)
					m2 = None
				m2 = re.search('DTEND',line)
				if m2 != None:
					m3 = re.search(r'(?<=:)\d+',line)
					self.end_date = m3.group(0)
					m2 = None
				m2 = re.search('SUMMARY',line)
				if m2 != None:
					m3 = re.search(r'(?<=:)\D+',line)
					self.summary = m3.group(0)
					m2 = None
				
			if self.start_date != None and self.end_date != None and self.summary != None:
				start_date_year = int(self.start_date[0:4])
				start_date_month = int(self.start_date[4:6])
				start_date_day = int(self.start_date[6:8])
				self.start_date = datetime.date(start_date_year, start_date_month, start_date_day)
				end_date_year = int(self.end_date[0:4])
				end_date_month = int(self.end_date[4:6])
				end_date_day = int(self.end_date[6:8])
				self.end_date = datetime.date(end_date_year, end_date_month, end_date_day)
				NewEvent = CalEvent(self.summary, self.start_date, self.end_date)
				self.add_event(NewEvent)
				self.start_date = None
				self.end_date = None
				self.summary = None
			if m2 != None:
				self.isItAnEvent = False
				

	def events_on_date(self,date):
		"""Collects events on a given datetime.date in the eventsOnDate list"""
		for event in self.dictionary:
			if event.occurs_on_day(date) == True:
				self.eventsOnDate.append(event)
		if not self.eventsOnDate:
			# if list is empty
			print "no events found for that date"
			return
			
	def events_today(self):
		"""Collects events today in the eventsToday list"""
		today = datetime.datetime.date(self.today)
		for event in self.dictionary:
			if event.occurs_on_day(today) == True:
				self.eventsToday.append(event)
		print self.eventsToday
		if not self.eventsToday:
			print "no events found for that date"
				
	def events(self):
		"""Prints the list of events (dictionary)"""
		for event in self.dictionary:
			print event
		
		

			
		