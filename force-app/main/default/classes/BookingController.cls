/**
 * BookingController
 * --------------------------------------------------
 * Entry point for LWC. Handles all @AuraEnabled methods.
 * Delegates business logic to BookingService.
 */
public with sharing class BookingController {
    
    // ============================================
    // Get all theatres for dropdown
    // ============================================
    @AuraEnabled(cacheable=true)
    public static List<Theatre__c> getTheatres() {
        try {
            return [
                SELECT Id, Name, Theatre_Capacity__c 
                FROM Theatre__c 
                WITH SECURITY_ENFORCED
                ORDER BY Name ASC
                LIMIT 1000
            ];
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'getTheatres Error: ' + e.getMessage());
            throw new AuraHandledException('Failed to load theatres.');
        }
    }
    
    
    // ============================================
    // Get movies by theatre (for typeahead search)
    // ============================================
    @AuraEnabled(cacheable=true)
    public static List<Movie__c> getMoviesByTheatre(Id theatreId) {
        try {
            if (String.isBlank(theatreId)) {
                return new List<Movie__c>();
            }
            
            return [
                SELECT Id, Name, Duration__c,
                       Booked_Seat__c, Available_Seats__c,
                       Theatre__c, Theatre__r.Name, 
                       Theatre__r.Theatre_Capacity__c
                FROM Movie__c 
                WHERE Theatre__c = :theatreId
                WITH SECURITY_ENFORCED
                ORDER BY Name ASC
                LIMIT 1000
            ];
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'getMoviesByTheatre Error: ' + e.getMessage());
            throw new AuraHandledException('Failed to load movies.');
        }
    }
    
    // ============================================
    // Get picklist values dynamically
    // Used by LWC to populate Show Time dropdown
    // ============================================
    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getShowTimeOptions() {
        List<PicklistOption> options = new List<PicklistOption>();
        
        try {
            Schema.DescribeFieldResult fieldDescribe = 
                Booking__c.S__c.getDescribe();
            
            for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
                if (entry.isActive()) {
                    PicklistOption option = new PicklistOption();
                    option.label = entry.getLabel();
                    option.value = entry.getValue();
                    options.add(option);
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 
                'getShowTimeOptions Error: ' + e.getMessage());
            throw new AuraHandledException('Failed to load show times.');
        }
        
        return options;
    }

    // ============================================
    // Wrapper class for picklist options
    // ============================================
    public class PicklistOption {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String value { get; set; }
    }

    
    // ============================================
    // Get specific movie details (for seat counters)
    // ============================================
    @AuraEnabled(cacheable=true)
    public static Movie__c getMovieDetails(Id movieId) {
        try {
            if (String.isBlank(movieId)) {
                return null;
            }
            
            List<Movie__c> movies = [
                SELECT Id, Name, Duration__c,
                       Booked_Seat__c, Available_Seats__c,
                       Theatre__c, Theatre__r.Name, 
                       Theatre__r.Theatre_Capacity__c
                FROM Movie__c 
                WHERE Id = :movieId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            
            return movies.isEmpty() ? null : movies[0];
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'getMovieDetails Error: ' + e.getMessage());
            throw new AuraHandledException('Failed to load movie details.');
        }
    }


    // ============================================
    // Get booked & available seats
    // for a specific Movie + Theatre + ShowTime + Date slot
    // ============================================
    @AuraEnabled(cacheable=false)
    public static SlotSeatInfo getSeatsBySlot(Id movieId, Id theatreId, String showTime, Date bookingDate) {
        try {
            if (String.isBlank(movieId) || String.isBlank(theatreId) || String.isBlank(showTime) || bookingDate == null) {
                throw new AuraHandledException('Movie, Theatre, Show Time ani Date select kara.');
            }

            List<Theatre__c> theatres = [
                SELECT Id, Theatre_Capacity__c
                FROM Theatre__c
                WHERE Id = :theatreId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            if (theatres.isEmpty()) {
                throw new AuraHandledException('Theatre sapdla nahi.');
            }

            Integer totalCapacity = (Integer)(theatres[0].Theatre_Capacity__c != null 
                ? theatres[0].Theatre_Capacity__c : 0);

            AggregateResult[] results = [
                SELECT SUM(Number_of_Seats__c) totalBooked
                FROM Booking__c
                WHERE Movie__c = :movieId
                  AND Theatre__c = :theatreId
                  AND S__c = :showTime
                  AND Booking_Date__c = :bookingDate
                WITH SECURITY_ENFORCED
            ];

            Integer bookedCount = 0;
            if (!results.isEmpty() && results[0].get('totalBooked') != null) {
                bookedCount = ((Decimal) results[0].get('totalBooked')).intValue();
            }

            Integer availableCount = totalCapacity - bookedCount;
            if (availableCount < 0) availableCount = 0;

            SlotSeatInfo info = new SlotSeatInfo();
            info.bookedSeats    = bookedCount;
            info.availableSeats = availableCount;
            info.totalCapacity  = totalCapacity;
            return info;

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'getSeatsBySlot Error: ' + e.getMessage());
            throw new AuraHandledException('Failed to load seat info.');
        }
    }

    // ============================================
    // Wrapper for slot seat info
    // ============================================
    public class SlotSeatInfo {
        @AuraEnabled public Integer bookedSeats    { get; set; }
        @AuraEnabled public Integer availableSeats { get; set; }
        @AuraEnabled public Integer totalCapacity  { get; set; }
    }

    
    // ============================================
    // Create new movie (if not in database)
    // ✅ Booked_Seat__c kadhla — formula field ahe, write hot nahi
    // ============================================
    @AuraEnabled
    public static Movie__c createNewMovie(String movieName, Id theatreId) {
        try {
            if (String.isBlank(movieName)) {
                throw new AuraHandledException('Movie name is required.');
            }
            if (String.isBlank(theatreId)) {
                throw new AuraHandledException('Please select a theatre first.');
            }
            
            String searchName = movieName.trim().toLowerCase();
            List<Movie__c> existing = [
                SELECT Id, Name FROM Movie__c 
                WHERE Theatre__c = :theatreId
                WITH SECURITY_ENFORCED
                LIMIT 1000
            ];
            
            for (Movie__c m : existing) {
                if (m.Name.toLowerCase() == searchName) {
                    throw new AuraHandledException(
                        'Movie "' + movieName + '" already exists in this theatre.'
                    );
                }
            }
            
            if (!Schema.sObjectType.Movie__c.isCreateable()) {
                throw new AuraHandledException('You do not have permission to create movies.');
            }
            
            // ✅ Booked_Seat__c SET KARAT NAHI — formula field ahe
            Movie__c newMovie = new Movie__c(
                Name = movieName.trim(),
                Theatre__c = theatreId,
                Duration__c = 2.30
            );
            insert newMovie;
            
            return [
                SELECT Id, Name, Duration__c,
                       Booked_Seat__c, Available_Seats__c,
                       Theatre__c, Theatre__r.Name, 
                       Theatre__r.Theatre_Capacity__c
                FROM Movie__c 
                WHERE Id = :newMovie.Id
            ];
            
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'createNewMovie Error: ' + e.getMessage());
            throw new AuraHandledException('Failed to create movie: ' + e.getMessage());
        }
    }
    
    
    // ============================================
    // Save booking (Confirm Booking button)
    // ============================================
    @AuraEnabled
    public static String createBooking(BookingWrapper bookingData) {
        try {
            return BookingService.saveBooking(bookingData);
        } catch (BookingException e) {
            System.debug(LoggingLevel.WARN, 'Validation Error: ' + e.getMessage());
            throw new AuraHandledException(e.getMessage());
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 
                'Unexpected Error: ' + e.getMessage() + 
                '\nStack: ' + e.getStackTraceString());
            throw new AuraHandledException(
                'Failed to save booking. Please try again later.'
            );
        }
    }
    
    
    // ============================================
    // Wrapper class for LWC data transfer
    // ============================================
    public class BookingWrapper {
        @AuraEnabled public String firstName      { get; set; }
        @AuraEnabled public String lastName       { get; set; }
        @AuraEnabled public String email          { get; set; }
        @AuraEnabled public String phone          { get; set; }
        @AuraEnabled public String theatreId      { get; set; }
        @AuraEnabled public String movieId        { get; set; }
        @AuraEnabled public String showTime       { get; set; }
        @AuraEnabled public String ticketType     { get; set; }
        @AuraEnabled public Decimal ticketPrice   { get; set; }
        @AuraEnabled public Integer numberOfSeats { get; set; }
        @AuraEnabled public String paymentMode    { get; set; }
        @AuraEnabled public Decimal totalAmount   { get; set; }
        @AuraEnabled public Date    bookingDate   { get; set; } 
    }
}