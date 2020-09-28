import Alamofire
import OAuth2
import Foundation

public class SpotifyAPI {
    var authClient: OAuth2CodeGrant?
    
    static let manager = SpotifyAPI()
    
    private init() {}
    
    func initialize(clientId: String, redirectUris: [String], scopes: [AuthScope], usePkce: Bool = true, useKeychain: Bool = true) {
        authClient = OAuth2CodeGrant(settings: [
            "client_id": clientId,
            "authorize_uri": "https://accounts.spotify.com/authorize",
            "token_uri": "https://accounts.spotify.com/api/token",
            "redirect_uris": redirectUris,
            "use_pkce": usePkce,
            "scope": scopes.map{scope in scope.rawValue}.joined(separator: "%20"),
            "keychain": useKeychain,
        ] as OAuth2JSON)
    }
    
    func authorize(completion: @escaping (Bool) -> Void) {
        assert(authClient != nil, "Spotify manager not initialzed, call initialize() before use")
        authClient!.forgetTokens()
        authClient!.authorize(callback: {authParameters, error in
            if authParameters != nil {
                completion(true)
            }
            else {
                print("Authorization was canceled or went wrong: \(String(describing: error))")
                if error?.description == "Refresh token revoked" {
                    self.authClient!.forgetTokens()
                }
                completion(false)
            }
        })
    }
    
    func request<Object: Codable>(url: URL, completion: @escaping (Object?, Error?) -> Void) {
        assert(authClient != nil, "Spotify manager not initialzed, call initialize() before use")
        
        authClient!.authorize { (_,_) in
            
            var urlRequest = URLRequest(url: url)
            urlRequest.setValue("Bearer \(self.authClient!.accessToken!)", forHTTPHeaderField: "Authorization")
            
            URLSession.shared.dataTask(with: urlRequest) { (data, response, error) in
                guard error == nil else {
                    completion(nil, error)
                    return
                }
                
                guard let data = data else {
                    completion(nil, NSError(domain: "No data returned", code: 10, userInfo: nil))
                    return
                }
                
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                
                do {
                    let decoded = try decoder.decode(SpotifyError.self, from: data)
                    completion(nil, NSError(domain: decoded.message, code: decoded.status, userInfo: nil))
                    return
                } catch {}
                
                do {
                    let decoded = try decoder.decode(Object.self, from: data)
                    completion(decoded, nil)
                } catch let parseError {
                    if let json = try? JSONSerialization.jsonObject(with: data, options: []) {
                        print(json)
                    }
                    completion(nil, parseError)
                }
            }.resume()
        }
    }
    
    func paginatedRequest<Object: Codable>(url: URL, objects: [Object] = [], completion: @escaping ([Object], Error?) -> Void) {
        request(url: url) { (paginatedObjects: Paging<Object>?, error) in
            guard let paginatedObjects = paginatedObjects else {
                completion(objects, error)
                return
            }
            guard error == nil else {
                completion(objects, error)
                return
            }
            var newObjects = objects
            newObjects.append(contentsOf: paginatedObjects.items)
            if paginatedObjects.next != nil {
                self.paginatedRequest(url: paginatedObjects.next!, objects: newObjects, completion: completion)
            } else {
                completion(newObjects, error)
            }
        }
    }
    
    func getOwnUserProfile(completion: @escaping (UserPublic?, Error?) -> Void) {
        
        let url = baseUrl.appendingPathComponent(Endpoints[.me])
        self.request(url: url, completion: completion)
        
    }
    
    // MARK: - Playlists
    
    func getPlaylist(id: String, completion: @escaping (Playlist?, Error?) -> Void) {
        let url = baseUrl.appendingPathComponent(Endpoints[.playlists]).appendingPathComponent(id)
        self.request(url: url, completion: completion)
    }
    
    func getUserPlaylists(id: String, completion: @escaping ([PlaylistSimplified], Error?) -> Void) {
        let url = baseUrl.appendingPathComponent(Endpoints[.users])
            .appendingPathComponent(id)
            .appendingPathComponent(Endpoints[.playlists])
        paginatedRequest(url: url, completion: completion)
    }
    
    // MARK: - Tracks
    
    func getTrack(id: String, completion: @escaping (Track?, Error?) -> Void) {
        let url = baseUrl.appendingPathComponent(Endpoints[.tracks]).appendingPathComponent(id)
        request(url: url, completion: completion)
    }
    
    // MARK: - Albums
    
    func getAlbum(id: String, completion: @escaping (Album?, Error?) -> Void) {
        let url = baseUrl.appendingPathComponent(Endpoints[.albums]).appendingPathComponent(id)
        request(url: url, completion: completion)
    }
    
    // MARK: - Artists
    
    func getArtist(id: String, completion: @escaping (Artist?, Error?) -> Void) {
        let url = baseUrl.appendingPathComponent(Endpoints[.artists]).appendingPathComponent(id)
        request(url: url, completion: completion)
    }
}
