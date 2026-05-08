/**
 * BookingService
 * --------------------------------------------------
 * Business logic for booking creation.
 * BULKIFIED — single ani multiple bookings donhi handle karta yeil.
 * Governor limits, security, validations sagla yethe.
 * 
 * ✅ UPDATED:
 *   - Movie cha Ticket_Price__c kadhla query madhun
 *   - Seat check aata SLOT-WISE hota 
 *     (Theatre + Movie + Date + ShowTime cha combination ne)
 *   - Booking object var Ticket_Price__c TASACH ahe (LWC madhun yeto)
 * 
 * @author  Shrikant Khedkar
 * @date    May 2026
 */
public with sharing class BookingService {
    
    // ===== Constants =====
    private static final Integer MAX_SEATS_PER_BOOKING = 10;
    private static final Integer MIN_SEATS_PER_BOOKING = 1;
    private static final Integer BULK_LIMIT = 200;
    private static final String EMAIL_REGEX = '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$';
    private static final String PHONE_REGEX = '^[0-9]{10}$';
    
    
    /**
     * Single booking save — bulk method internally call karta.
     */
    public static String saveBooking(BookingController.BookingWrapper data) {
        List<BookingController.BookingWrapper> wrappers = 
            new List<BookingController.BookingWrapper>{ data };
        
        List<String> ids = saveBookingsBulk(wrappers);
        return ids.isEmpty() ? null : ids[0];
    }
    
    
    /**
     * BULK save — multiple bookings ek shot madhe.
     * ✅ Slot-wise (Theatre + Movie + Date + ShowTime) seat check.
     */
    public static List<String> saveBookingsBulk(
        List<BookingController.BookingWrapper> dataList
    ) {
        // ===== 1. Input validation =====
        if (dataList == null || dataList.isEmpty()) {
            throw new BookingException('Booking data milala nahi.');
        }
        
        if (dataList.size() > BULK_LIMIT) {
            throw new BookingException(
                'Maximum ' + BULK_LIMIT + ' bookings allowed per request.'
            );
        }
        
        // ===== 2. Validate each booking =====
        for (BookingController.BookingWrapper data : dataList) {
            validateBooking(data);
        }
        
        // ===== 3. Collect unique IDs/emails (bulkification) =====
        Set<Id> movieIds   = new Set<Id>();
        Set<Id> theatreIds = new Set<Id>();
        Set<String> emails = new Set<String>();
        
        // Same slot sathi multiple bookings asle tar seats add kar
        // Key = movieId|theatreId|showTime|bookingDate
        Map<String, Integer> requestedBySlot = new Map<String, Integer>();
        
        for (BookingController.BookingWrapper data : dataList) {
            movieIds.add(data.movieId);
            theatreIds.add(data.theatreId);
            emails.add(data.email.toLowerCase());
            
            String slotKey = buildSlotKey(
                data.movieId, data.theatreId, data.showTime, data.bookingDate
            );
            Integer existing = requestedBySlot.containsKey(slotKey) 
                ? requestedBySlot.get(slotKey) : 0;
            requestedBySlot.put(slotKey, existing + data.numberOfSeats);
        }
        
        // ===== 4. SLOT-WISE seat availability check =====
        // 4a. Theatre capacity ana (1 SOQL — bulkified)
        Map<Id, Theatre__c> theatreMap = new Map<Id, Theatre__c>([
            SELECT Id, Name, Theatre_Capacity__c
            FROM Theatre__c 
            WHERE Id IN :theatreIds
            WITH SECURITY_ENFORCED
        ]);
        
        // 4b. Movie names ana — error messages sathi
        // ✅ Ticket_Price__c kadhla (Movie var aata field nahi)
        Map<Id, Movie__c> movieMap = new Map<Id, Movie__c>([
            SELECT Id, Name 
            FROM Movie__c 
            WHERE Id IN :movieIds
            WITH SECURITY_ENFORCED
        ]);
        
        // 4c. Pratek slot sathi already booked seats count kar (1 SOQL)
        AggregateResult[] slotBookings = [
            SELECT Movie__c movieId, Theatre__c theatreId, 
                   S__c showTime, Booking_Date__c bookingDate,
                   SUM(Number_of_Seats__c) totalBooked
            FROM Booking__c
            WHERE Movie__c IN :movieIds
              AND Theatre__c IN :theatreIds
            WITH SECURITY_ENFORCED
            GROUP BY Movie__c, Theatre__c, S__c, Booking_Date__c
        ];
        
        // Map: slotKey → already booked count
        Map<String, Integer> bookedBySlot = new Map<String, Integer>();
        for (AggregateResult ar : slotBookings) {
            String key = buildSlotKey(
                (Id)ar.get('movieId'),
                (Id)ar.get('theatreId'),
                (String)ar.get('showTime'),
                (Date)ar.get('bookingDate')
            );
            Integer booked = ((Decimal)ar.get('totalBooked')).intValue();
            bookedBySlot.put(key, booked);
        }
        
        // 4d. Pratek slot sathi: capacity vs (already booked + requested) check
        for (String slotKey : requestedBySlot.keySet()) {
            // slotKey format: movieId|theatreId|showTime|bookingDate
            String[] parts = slotKey.split('\\|');
            Id mId = (Id) parts[0];
            Id tId = (Id) parts[1];
            
            Theatre__c theatre = theatreMap.get(tId);
            if (theatre == null) {
                throw new BookingException('Theatre sapdla nahi.');
            }
            
            Movie__c movie = movieMap.get(mId);
            String movieName = (movie != null) ? movie.Name : 'this movie';
            
            Integer capacity = theatre.Theatre_Capacity__c != null 
                ? theatre.Theatre_Capacity__c.intValue() : 0;
            Integer alreadyBooked = bookedBySlot.containsKey(slotKey) 
                ? bookedBySlot.get(slotKey) : 0;
            Integer requested = requestedBySlot.get(slotKey);
            Integer available = capacity - alreadyBooked;
            if (available < 0) available = 0;
            
            if (available < requested) {
                throw new BookingException(
                    'Faqt ' + available + ' seats available ahet "' + 
                    movieName + '" cha ya slot sathi (' + 
                    parts[2] + ' on ' + parts[3] + ').'
                );
            }
        }
        
        // ===== 5. Contacts handle kar (BULKIFIED upsert) =====
        Map<String, Contact> contactMap = upsertContactsBulk(dataList, emails);
        
        // ===== 6. Bookings build kar (memory madhe) =====
        // ✅ Ticket_Price__c — Booking object var TASACH ahe (LWC madhun yeto)
        List<Booking__c> bookingsToInsert = new List<Booking__c>();
        
        for (BookingController.BookingWrapper data : dataList) {
            Contact con = contactMap.get(data.email.toLowerCase());
            
            bookingsToInsert.add(new Booking__c(
                Contact__c = con.Id,
                Movie__c = data.movieId,
                Theatre__c = data.theatreId,
                Booking_Date__c = data.bookingDate != null 
                            ? data.bookingDate 
                            : Date.today(),
                S__c = data.showTime,
                Number_of_Seats__c = data.numberOfSeats,
                Ticket_Type__c = data.ticketType,
                Ticket_Price__c = data.ticketPrice,   // ✅ Booking var save hota
                Mode_of_Payment__c = data.paymentMode
            ));
        }
        
        // ===== 7. CRUD check =====
        if (!Schema.sObjectType.Booking__c.isCreateable()) {
            throw new BookingException(
                'Tumhala booking create karaychi permission nahi.'
            );
        }
        
        // ===== 8. Governor limit check =====
        checkGovernorLimits();
        
        // ===== 9. Single DML insert (bulk) =====
        Database.SaveResult[] results = Database.insert(bookingsToInsert, false);
        
        // ===== 10. Process results =====
        List<String> insertedIds = new List<String>();
        List<String> errors = new List<String>();
        
        for (Database.SaveResult sr : results) {
            if (sr.isSuccess()) {
                insertedIds.add(sr.getId());
            } else {
                for (Database.Error err : sr.getErrors()) {
                    errors.add(err.getMessage());
                }
            }
        }
        
        if (!errors.isEmpty()) {
            System.debug(LoggingLevel.ERROR, 
                'Booking insert errors: ' + errors);
            throw new BookingException(String.join(errors, '; '));
        }
        
        return insertedIds;
    }
    
    
    // ============================================
    // PRIVATE: Slot key builder
    // Theatre + Movie + ShowTime + Date cha unique key
    // ============================================
    private static String buildSlotKey(Id movieId, Id theatreId, String showTime, Date bookingDate) {
        return String.valueOf(movieId) + '|' + 
               String.valueOf(theatreId) + '|' + 
               showTime + '|' + 
               String.valueOf(bookingDate);
    }
    
    
    // ============================================
    // PRIVATE: Bulk contact upsert
    // ============================================
    private static Map<String, Contact> upsertContactsBulk(
        List<BookingController.BookingWrapper> dataList,
        Set<String> emails
    ) {
        // 1 SOQL — saglya existing contacts ana
        Map<String, Contact> existingContacts = new Map<String, Contact>();
        for (Contact c : [
            SELECT Id, FirstName, LastName, Email, Phone
            FROM Contact 
            WHERE Email IN :emails
            WITH SECURITY_ENFORCED
        ]) {
            existingContacts.put(c.Email.toLowerCase(), c);
        }
        
        // Same email multiple times asla tar latest data thev
        Map<String, BookingController.BookingWrapper> latestByEmail = 
            new Map<String, BookingController.BookingWrapper>();
        for (BookingController.BookingWrapper data : dataList) {
            latestByEmail.put(data.email.toLowerCase(), data);
        }
        
        List<Contact> toInsert = new List<Contact>();
        List<Contact> toUpdate = new List<Contact>();
        
        for (String email : latestByEmail.keySet()) {
            BookingController.BookingWrapper data = latestByEmail.get(email);
            
            if (existingContacts.containsKey(email)) {
                Contact existing = existingContacts.get(email);
                existing.FirstName = data.firstName;
                existing.LastName = data.lastName;
                existing.Phone = data.phone;
                toUpdate.add(existing);
            } else {
                toInsert.add(new Contact(
                    FirstName = data.firstName,
                    LastName = data.lastName,
                    Email = data.email,
                    Phone = data.phone
                ));
            }
        }
        
        // CRUD check
        if (!Schema.sObjectType.Contact.isCreateable()) {
            throw new BookingException(
                'Tumhala contact create karaychi permission nahi.'
            );
        }
        
        // Bulk DML (max 2 statements)
        if (!toInsert.isEmpty()) {
            Database.insert(toInsert, false);
        }
        if (!toUpdate.isEmpty()) {
            Database.update(toUpdate, false);
        }
        
        // Final map (existing + newly inserted)
        Map<String, Contact> finalMap = new Map<String, Contact>();
        finalMap.putAll(existingContacts);
        for (Contact c : toInsert) {
            finalMap.put(c.Email.toLowerCase(), c);
        }
        
        return finalMap;
    }
    
    
    // ============================================
    // PRIVATE: Validation
    // ============================================
    private static void validateBooking(BookingController.BookingWrapper data) {
        if (data == null) {
            throw new BookingException('Booking data milala nahi.');
        }
        
        // Personal Info
        if (String.isBlank(data.firstName)) {
            throw new BookingException('First Name required ahe.');
        }
        if (String.isBlank(data.lastName)) {
            throw new BookingException('Last Name required ahe.');
        }
        if (String.isBlank(data.email)) {
            throw new BookingException('Email required ahe.');
        }
        if (!Pattern.matches(EMAIL_REGEX, data.email)) {
            throw new BookingException('Email format chuk ahe.');
        }
        if (String.isBlank(data.phone)) {
            throw new BookingException('Phone Number required ahe.');
        }
        if (!Pattern.matches(PHONE_REGEX, data.phone)) {
            throw new BookingException('Phone Number 10 digits cha pahije.');
        }
        
        // Venue
        if (String.isBlank(data.theatreId)) {
            throw new BookingException('Theatre select kara.');
        }
        if (String.isBlank(data.movieId)) {
            throw new BookingException('Movie select kara.');
        }
        if (String.isBlank(data.showTime)) {
            throw new BookingException('Show Time select kara.');
        }
        if (data.bookingDate == null) {
            throw new BookingException('Booking Date select kara.');
        }
        if (data.bookingDate < Date.today()) {
            throw new BookingException('Booking Date cannot be a past date.');
        }
        
        // Ticket
        if (String.isBlank(data.ticketType)) {
            throw new BookingException('Ticket Type select kara.');
        }
        if (data.numberOfSeats == null || data.numberOfSeats < MIN_SEATS_PER_BOOKING) {
            throw new BookingException('Atleast 1 seat select kara.');
        }
        if (data.numberOfSeats > MAX_SEATS_PER_BOOKING) {
            throw new BookingException(
                'Maximum ' + MAX_SEATS_PER_BOOKING + ' seats per booking.'
            );
        }
        
        // Payment
        if (String.isBlank(data.paymentMode)) {
            throw new BookingException('Payment Mode select kara.');
        }
    }
    
    
    // ============================================
    // PRIVATE: Governor Limits Safety Check
    // ============================================
    private static void checkGovernorLimits() {
        // SOQL queries threshold (80%)
        Integer queriesUsed = Limits.getQueries();
        Integer queriesMax = Limits.getLimitQueries();
        
        if (queriesUsed >= (queriesMax * 80 / 100)) {
            System.debug(LoggingLevel.WARN, 
                'SOQL Warning: ' + queriesUsed + '/' + queriesMax);
        }
        
        // DML statements threshold
        Integer dmlUsed = Limits.getDMLStatements();
        Integer dmlMax = Limits.getLimitDMLStatements();
        
        if (dmlUsed >= dmlMax - 5) {
            throw new BookingException(
                'System busy ahe, krupaya nantar try kara.'
            );
        }
        
        // CPU time threshold
        Integer cpuUsed = Limits.getCpuTime();
        Integer cpuMax = Limits.getLimitCpuTime();
        
        if (cpuUsed >= (cpuMax * 80 / 100)) {
            System.debug(LoggingLevel.WARN, 
                'CPU Warning: ' + cpuUsed + 'ms / ' + cpuMax + 'ms');
        }
    }
}